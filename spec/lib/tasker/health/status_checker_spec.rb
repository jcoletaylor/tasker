# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Health::StatusChecker, type: :model do
  include ActiveSupport::Testing::TimeHelpers
  describe '.status' do
    context 'with healthy system' do
      before do
        # Mock the health counts function to return test data as HealthMetrics object
        health_metrics = Tasker::Functions::FunctionBasedSystemHealthCounts::HealthMetrics.new(
          total_tasks: 25,
          pending_tasks: 10,
          in_progress_tasks: 5,
          complete_tasks: 8,
          error_tasks: 2,
          cancelled_tasks: 0,
          total_steps: 100,
          pending_steps: 40,
          in_progress_steps: 20,
          complete_steps: 32,
          error_steps: 8,
          retryable_error_steps: 6,
          exhausted_retry_steps: 2,
          in_backoff_steps: 3,
          active_connections: 5,
          max_connections: 100
        )

        allow(Tasker::Functions::FunctionBasedSystemHealthCounts)
          .to receive(:call)
          .and_return(health_metrics)
      end

      it 'returns comprehensive status data' do
        result = described_class.status

        expect(result).to have_key(:healthy)
        expect(result).to have_key(:timestamp)
        expect(result).to have_key(:metrics)
        expect(result).to have_key(:database)

        expect(result[:healthy]).to be true
        expect(result[:timestamp]).to be_within(1.second).of(Time.current)
      end

      it 'includes task metrics' do
        result = described_class.status

        task_metrics = result[:metrics][:tasks]
        expect(task_metrics[:total]).to eq(25)
        expect(task_metrics[:pending]).to eq(10)
        expect(task_metrics[:in_progress]).to eq(5)
        expect(task_metrics[:complete]).to eq(8)
        expect(task_metrics[:error]).to eq(2)
        expect(task_metrics[:cancelled]).to eq(0)
      end

      it 'includes step metrics' do
        result = described_class.status

        step_metrics = result[:metrics][:steps]
        expect(step_metrics[:total]).to eq(100)
        expect(step_metrics[:pending]).to eq(40)
        expect(step_metrics[:in_progress]).to eq(20)
        expect(step_metrics[:complete]).to eq(32)
        expect(step_metrics[:error]).to eq(8)
      end

      it 'includes retry metrics' do
        result = described_class.status

        retry_metrics = result[:metrics][:retries]
        expect(retry_metrics[:retryable_errors]).to eq(6)
        expect(retry_metrics[:exhausted_retries]).to eq(2)
        expect(retry_metrics[:in_backoff]).to eq(3)
      end

      it 'includes database metrics' do
        result = described_class.status

        db_metrics = result[:database]
        expect(db_metrics[:active_connections]).to eq(5)
        expect(db_metrics[:max_connections]).to eq(100)
        expect(db_metrics[:connection_utilization]).to eq(5.0) # 5/100 * 100
      end
    end

    context 'when health function fails' do
      before do
        allow(Tasker::Functions::FunctionBasedSystemHealthCounts).to receive(:call).and_raise(ActiveRecord::ConnectionNotEstablished)
      end

      it 'returns unhealthy status' do
        result = described_class.status

        expect(result[:healthy]).to be false
        expect(result).to have_key(:error)
        expect(result[:error]).to include('ConnectionNotEstablished')
      end

      it 'includes basic structure even on failure' do
        result = described_class.status

        expect(result).to have_key(:healthy)
        expect(result).to have_key(:timestamp)
        expect(result).to have_key(:error)
      end
    end

    context 'with zero max connections' do
      before do
        health_metrics = Tasker::Functions::FunctionBasedSystemHealthCounts::HealthMetrics.new(
          total_tasks: 5,
          pending_tasks: 0,
          in_progress_tasks: 0,
          complete_tasks: 0,
          error_tasks: 0,
          cancelled_tasks: 0,
          total_steps: 0,
          pending_steps: 0,
          in_progress_steps: 0,
          complete_steps: 0,
          error_steps: 0,
          retryable_error_steps: 0,
          exhausted_retry_steps: 0,
          in_backoff_steps: 0,
          active_connections: 2,
          max_connections: 0 # Edge case
        )

        allow(Tasker::Functions::FunctionBasedSystemHealthCounts).to receive(:call).and_return(health_metrics)
      end

      it 'handles division by zero gracefully' do
        result = described_class.status

        expect(result[:database][:connection_utilization]).to eq(0.0)
      end
    end
  end

  describe 'caching behavior' do
    around do |example|
      # Clear cache before and after each test
      Rails.cache.clear
      example.run
      Rails.cache.clear
    end

    it 'caches results for 15 seconds' do
      # Mock the function to return different values on subsequent calls
      call_count = 0
      allow(Tasker::Functions::FunctionBasedSystemHealthCounts).to receive(:call) do
        call_count += 1
        Tasker::Functions::FunctionBasedSystemHealthCounts::HealthMetrics.new(
          total_tasks: call_count,
          pending_tasks: 0,
          in_progress_tasks: 0,
          complete_tasks: 0,
          error_tasks: 0,
          cancelled_tasks: 0,
          total_steps: 0,
          pending_steps: 0,
          in_progress_steps: 0,
          complete_steps: 0,
          error_steps: 0,
          retryable_error_steps: 0,
          exhausted_retry_steps: 0,
          in_backoff_steps: 0,
          active_connections: 1,
          max_connections: 10
        )
      end

      # Mock cache to simulate proper caching behavior
      cache_data = nil
      allow(Rails.cache).to receive(:read) { |_key| cache_data }
      allow(Rails.cache).to receive(:write) { |_key, value, _options|
        cache_data = value
        true
      }

      # First call should execute function and cache result
      result1 = described_class.status
      expect(result1[:metrics][:tasks][:total]).to eq(1)
      expect(result1[:cached]).to be false

      # Second call within 15 seconds should return cached result
      result2 = described_class.status
      expect(result2[:metrics][:tasks][:total]).to eq(1) # Same as first call
      expect(result2[:cached]).to be true

      expect(call_count).to eq(1) # Function called only once
    end

    it 'refreshes cache after 15 seconds' do
      call_count = 0
      allow(Tasker::Functions::FunctionBasedSystemHealthCounts).to receive(:call) do
        call_count += 1
        Tasker::Functions::FunctionBasedSystemHealthCounts::HealthMetrics.new(
          total_tasks: call_count,
          pending_tasks: 0,
          in_progress_tasks: 0,
          complete_tasks: 0,
          error_tasks: 0,
          cancelled_tasks: 0,
          total_steps: 0,
          pending_steps: 0,
          in_progress_steps: 0,
          complete_steps: 0,
          error_steps: 0,
          retryable_error_steps: 0,
          exhausted_retry_steps: 0,
          in_backoff_steps: 0,
          active_connections: 1,
          max_connections: 10
        )
      end

      # First call
      result1 = described_class.status
      expect(result1[:metrics][:tasks][:total]).to eq(1)

      # Simulate time passing
      travel 16.seconds do
        result2 = described_class.status
        expect(result2[:metrics][:tasks][:total]).to eq(2) # New value
      end

      expect(call_count).to eq(2) # Function called twice
    end

    it 'handles cache errors gracefully' do
      # Mock cache to fail
      allow(Rails.cache).to receive(:read).and_raise(StandardError.new('Cache unavailable'))

      # Mock the function to return data
      health_metrics = Tasker::Functions::FunctionBasedSystemHealthCounts::HealthMetrics.new(
        total_tasks: 10,
        pending_tasks: 0,
        in_progress_tasks: 0,
        complete_tasks: 0,
        error_tasks: 0,
        cancelled_tasks: 0,
        total_steps: 0,
        pending_steps: 0,
        in_progress_steps: 0,
        complete_steps: 0,
        error_steps: 0,
        retryable_error_steps: 0,
        exhausted_retry_steps: 0,
        in_backoff_steps: 0,
        active_connections: 1,
        max_connections: 10
      )

      allow(Tasker::Functions::FunctionBasedSystemHealthCounts).to receive(:call).and_return(health_metrics)

      # Should still work without cache
      result = described_class.status
      expect(result[:healthy]).to be true
      expect(result[:metrics][:tasks][:total]).to eq(10)
    end

    it 'uses correct cache key' do
      expect(Rails.cache).to receive(:read).with('tasker:health:status').and_return(nil)
      expect(Rails.cache).to receive(:write).with('tasker:health:status', anything, expires_in: 15.seconds)

      health_metrics = Tasker::Functions::FunctionBasedSystemHealthCounts::HealthMetrics.new(
        total_tasks: 5,
        pending_tasks: 0,
        in_progress_tasks: 0,
        complete_tasks: 0,
        error_tasks: 0,
        cancelled_tasks: 0,
        total_steps: 0,
        pending_steps: 0,
        in_progress_steps: 0,
        complete_steps: 0,
        error_steps: 0,
        retryable_error_steps: 0,
        exhausted_retry_steps: 0,
        in_backoff_steps: 0,
        active_connections: 1,
        max_connections: 10
      )

      allow(Tasker::Functions::FunctionBasedSystemHealthCounts).to receive(:call).and_return(health_metrics)

      described_class.status
    end
  end

  describe 'data type conversion' do
    before do
      # Test with HealthMetrics object
      health_metrics = Tasker::Functions::FunctionBasedSystemHealthCounts::HealthMetrics.new(
        total_tasks: 42,
        pending_tasks: 10,
        in_progress_tasks: 0,
        complete_tasks: 0,
        error_tasks: 0,
        cancelled_tasks: 0,
        total_steps: 0,
        pending_steps: 0,
        in_progress_steps: 0,
        complete_steps: 0,
        error_steps: 0,
        retryable_error_steps: 0,
        exhausted_retry_steps: 0,
        in_backoff_steps: 0,
        active_connections: 3,
        max_connections: 50
      )

      allow(Tasker::Functions::FunctionBasedSystemHealthCounts).to receive(:call).and_return(health_metrics)
    end

    it 'converts string values to integers' do
      result = described_class.status

      expect(result[:metrics][:tasks][:total]).to be_an(Integer)
      expect(result[:metrics][:tasks][:total]).to eq(42)
      expect(result[:database][:active_connections]).to eq(3)
      expect(result[:database][:max_connections]).to eq(50)
    end

    it 'calculates connection utilization as float' do
      result = described_class.status

      expect(result[:database][:connection_utilization]).to be_a(Float)
      expect(result[:database][:connection_utilization]).to eq(6.0) # 3/50 * 100
    end
  end

  describe 'health determination' do
    it 'marks as healthy when function succeeds' do
      health_metrics = Tasker::Functions::FunctionBasedSystemHealthCounts::HealthMetrics.new(
        total_tasks: 10,
        pending_tasks: 0,
        in_progress_tasks: 0,
        complete_tasks: 0,
        error_tasks: 0,
        cancelled_tasks: 0,
        total_steps: 0,
        pending_steps: 0,
        in_progress_steps: 0,
        complete_steps: 0,
        error_steps: 0,
        retryable_error_steps: 0,
        exhausted_retry_steps: 0,
        in_backoff_steps: 0,
        active_connections: 1,
        max_connections: 10
      )

      allow(Tasker::Functions::FunctionBasedSystemHealthCounts).to receive(:call).and_return(health_metrics)

      result = described_class.status
      expect(result[:healthy]).to be true
    end

    it 'marks as unhealthy when function fails with database error' do
      allow(Tasker::Functions::FunctionBasedSystemHealthCounts).to receive(:call).and_raise(ActiveRecord::StatementTimeout)

      result = described_class.status
      expect(result[:healthy]).to be false
      expect(result[:error]).to include('StatementTimeout')
    end

    it 'marks as unhealthy when function fails with connection error' do
      allow(Tasker::Functions::FunctionBasedSystemHealthCounts).to receive(:call).and_raise(PG::ConnectionBad)

      result = described_class.status
      expect(result[:healthy]).to be false
      expect(result[:error]).to include('PG::ConnectionBad')
    end
  end

  describe 'integration with real function' do
    it 'works with actual health counts function' do
      # Create some test data
      create(:linear_workflow_task)

      # This test calls the real function
      result = described_class.status

      expect(result).to have_key(:healthy)
      expect(result).to have_key(:metrics)
      expect(result).to have_key(:database)
      expect(result[:metrics][:tasks][:total]).to be >= 1 # At least our test task
    end
  end
end
