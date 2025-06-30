# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Orchestration::ConnectionPoolIntelligence do
  let(:mock_pool) { instance_double(ActiveRecord::ConnectionAdapters::ConnectionPool) }
  let(:mock_config) { instance_double(Tasker::Types::ExecutionConfig) }

  before do
    allow(ActiveRecord::Base).to receive(:connection_pool).and_return(mock_pool)
    allow(Tasker.configuration).to receive(:execution).and_return(mock_config)

    # Default config values
    allow(mock_config).to receive_messages(min_concurrent_steps: 3, max_concurrent_steps_limit: 12, connection_pressure_factors: {
                                             low: 0.8,
                                             moderate: 0.6,
                                             high: 0.4,
                                             critical: 0.2
                                           })
  end

  describe '.assess_connection_health' do
    context 'with healthy connection pool' do
      before do
        allow(mock_pool).to receive_messages(stat: {
                                               size: 10,
                                               busy: 2,
                                               available: 8
                                             }, size: 10)
      end

      it 'returns comprehensive health assessment' do
        result = described_class.assess_connection_health

        expect(result).to include(
          pool_utilization: 0.2,
          connection_pressure: :low,
          health_status: :healthy,
          assessment_timestamp: be_within(1.second).of(Time.current)
        )
        expect(result[:rails_pool_stats]).to eq({
                                                  size: 10,
                                                  busy: 2,
                                                  available: 8
                                                })
        expect(result[:recommended_concurrency]).to be >= 3
      end
    end

    context 'with moderate pressure' do
      before do
        allow(mock_pool).to receive_messages(stat: {
                                               size: 10,
                                               busy: 6,
                                               available: 4
                                             }, size: 10)
      end

      it 'correctly identifies moderate pressure' do
        result = described_class.assess_connection_health

        expect(result).to include(
          pool_utilization: 0.6,
          connection_pressure: :moderate,
          health_status: :healthy
        )
      end
    end

    context 'with high pressure' do
      before do
        allow(mock_pool).to receive_messages(stat: {
                                               size: 10,
                                               busy: 8,
                                               available: 2
                                             }, size: 10)
      end

      it 'correctly identifies high pressure and degraded health' do
        result = described_class.assess_connection_health

        expect(result).to include(
          pool_utilization: 0.8,
          connection_pressure: :high,
          health_status: :degraded
        )
      end
    end

    context 'with critical pressure' do
      before do
        allow(mock_pool).to receive_messages(stat: {
                                               size: 10,
                                               busy: 9,
                                               available: 1
                                             }, size: 10)
      end

      it 'correctly identifies critical pressure and status' do
        result = described_class.assess_connection_health

        expect(result).to include(
          pool_utilization: 0.9,
          connection_pressure: :critical,
          health_status: :critical
        )
      end
    end

    context 'when connection pool access fails' do
      before do
        allow(ActiveRecord::Base).to receive(:connection_pool).and_raise(StandardError.new('Connection failed'))
      end

      it 'returns safe fallback assessment' do
        result = described_class.assess_connection_health

        expect(result).to include(
          pool_utilization: 0.0,
          connection_pressure: :unknown,
          recommended_concurrency: 3, # EMERGENCY_FALLBACK_CONCURRENCY
          health_status: :unknown,
          assessment_error: 'Connection failed'
        )
      end
    end
  end

  describe '.intelligent_concurrency_for_step_executor' do
    context 'with low pressure conditions' do
      before do
        allow(mock_pool).to receive_messages(stat: {
                                               size: 10,
                                               busy: 2,
                                               available: 8
                                             }, size: 10)
      end

      it 'returns higher concurrency for low pressure' do
        concurrency = described_class.intelligent_concurrency_for_step_executor

        expect(concurrency).to be >= 3
        expect(concurrency).to be <= 12
      end

      it 'logs debug information' do
        expect(Rails.logger).to receive(:debug) do |&block|
          log_message = block.call
          expect(log_message).to include('Dynamic concurrency')
          expect(log_message).to include('pressure=low')
          expect(log_message).to include('pool_size=10')
          expect(log_message).to include('available=8')
        end

        described_class.intelligent_concurrency_for_step_executor
      end
    end

    context 'with critical pressure conditions' do
      before do
        allow(mock_pool).to receive_messages(stat: {
                                               size: 10,
                                               busy: 9,
                                               available: 1
                                             }, size: 10)
      end

      it 'returns emergency fallback concurrency for critical pressure' do
        concurrency = described_class.intelligent_concurrency_for_step_executor

        expect(concurrency).to eq(3) # Should fall back to minimum
      end
    end

    context 'with custom pressure factors' do
      before do
        allow(mock_config).to receive(:connection_pressure_factors).and_return({
                                                                                 low: 0.9,
                                                                                 moderate: 0.7,
                                                                                 high: 0.5,
                                                                                 critical: 0.1
                                                                               })
        allow(mock_pool).to receive_messages(stat: {
                                               size: 10,
                                               busy: 2,
                                               available: 8
                                             }, size: 10)
      end

      it 'uses custom pressure factors for calculation' do
        concurrency = described_class.intelligent_concurrency_for_step_executor

        # With 8 available connections and 0.9 factor, should get higher concurrency
        expect(concurrency).to be >= 5
      end
    end

    context 'when assessment fails' do
      before do
        allow(described_class).to receive(:assess_connection_health).and_raise(StandardError.new('Assessment failed'))
      end

      it 'returns emergency fallback and logs error' do
        expect(Rails.logger).to receive(:error).with(
          a_string_including('Concurrency calculation failed').and(
            including('StandardError: Assessment failed').and(
              including('fallback=3')
            )
          )
        )

        concurrency = described_class.intelligent_concurrency_for_step_executor
        expect(concurrency).to eq(3)
      end
    end
  end

  describe 'pressure assessment constants' do
    it 'has correct pressure thresholds' do
      expect(described_class::PRESSURE_ASSESSMENT_THRESHOLDS).to eq({
                                                                      low: 0.0..0.5,
                                                                      moderate: 0.5..0.7,
                                                                      high: 0.7..0.85,
                                                                      critical: 0.85..Float::INFINITY
                                                                    })
    end

    it 'has conservative safety constants' do
      expect(described_class::MAX_SAFE_CONNECTION_PERCENTAGE).to eq(0.6)
      expect(described_class::EMERGENCY_FALLBACK_CONCURRENCY).to eq(3)
      expect(described_class::CONNECTION_UTILIZATION_PRECISION).to eq(3)
    end
  end

  describe 'utilization calculation precision' do
    before do
      allow(mock_pool).to receive_messages(stat: {
                                             size: 7,
                                             busy: 2,
                                             available: 5
                                           }, size: 7)
    end

    it 'calculates utilization with correct precision' do
      result = described_class.assess_connection_health

      # 2/7 = 0.285714... should round to 0.286 with 3 decimal places
      expect(result[:pool_utilization]).to eq(0.286)
    end
  end

  describe 'safety margin application' do
    context 'with moderate available connections' do
      before do
        allow(mock_pool).to receive_messages(stat: {
                                               size: 10,
                                               busy: 3,
                                               available: 7
                                             }, size: 10)
      end

      it 'applies 60% safety margin correctly' do
        result = described_class.assess_connection_health

        # 7 available connections * 0.6 = 4.2, floored = 4
        # But also needs to respect pressure factors and other constraints
        expect(result[:recommended_concurrency]).to be >= 3
        expect(result[:recommended_concurrency]).to be <= 7
      end
    end
  end
end
