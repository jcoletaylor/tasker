# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Telemetry::ExportCoordinator, type: :unit do
  let(:metrics_backend) { instance_double(Tasker::Telemetry::MetricsBackend) }
  let(:default_config) do
    {
      retention_window: 5.minutes,
      safety_margin: 1.minute,
      export_timeout: 2.minutes,
      max_retries: 3,
      retry_backoff_base: 30.seconds,
      lock_timeout: 5.minutes
    }
  end

  before do
    allow(Tasker::Telemetry::MetricsBackend).to receive(:instance).and_return(metrics_backend)
    allow(metrics_backend).to receive(:send).with(:detect_cache_capabilities).and_return({
                                                                                           atomic_operations: true,
                                                                                           distributed: true,
                                                                                           ttl_inspection: true
                                                                                         })
    allow(metrics_backend).to receive_messages(all_metrics: {}, export_distributed_metrics: { metrics: {} })
  end

  describe '#initialize' do
    it 'initializes with default configuration' do
      coordinator = described_class.new

      expect(coordinator.config).to include(default_config)
      expect(coordinator.instance_id).to be_present
      expect(coordinator.cache_capabilities).to be_a(Hash)
    end

    it 'merges custom configuration with defaults' do
      custom_config = { retention_window: 10.minutes, max_retries: 5 }
      coordinator = described_class.new(custom_config)

      expect(coordinator.config[:retention_window]).to eq(10.minutes)
      expect(coordinator.config[:max_retries]).to eq(5)
      expect(coordinator.config[:safety_margin]).to eq(1.minute) # Default preserved
    end

    it 'generates unique instance identifier' do
      # Mock time to advance between instances
      current_time = Time.current
      allow(Time).to receive(:current).and_return(current_time, current_time + 1)

      coordinator1 = described_class.new
      coordinator2 = described_class.new

      expect(coordinator1.instance_id).not_to eq(coordinator2.instance_id)
      expect(coordinator1.instance_id).to match(/\w+-\d+-\d+/)
    end
  end

  describe '#schedule_export' do
    let(:coordinator) { described_class.new }
    let(:timing_result) do
      {
        export_time: 3.minutes.from_now,
        ttl_expiry_time: 5.minutes.from_now,
        needs_ttl_extension: false,
        scheduling_reason: 'optimal_timing'
      }
    end

    before do
      allow(coordinator).to receive_messages(calculate_export_timing: timing_result,
                                             schedule_export_job: { job_id: 'job-123' })
    end

    it 'schedules export with default parameters' do
      result = coordinator.schedule_export

      expect(result).to include(
        success: true,
        format: :prometheus,
        scheduled_at: timing_result[:export_time],
        job_id: 'job-123'
      )
    end

    it 'schedules export with custom format' do
      expect(coordinator).to receive(:schedule_export_job).with(:json, timing_result)

      result = coordinator.schedule_export(format: :json)

      expect(result[:format]).to eq(:json)
    end

    it 'extends TTL when timing indicates need for extension' do
      timing_with_extension = timing_result.merge(
        needs_ttl_extension: true,
        extension_duration: 2.minutes
      )
      allow(coordinator).to receive(:calculate_export_timing).and_return(timing_with_extension)
      expect(coordinator).to receive(:extend_cache_ttl).with(2.minutes)

      coordinator.schedule_export
    end

    it 'handles scheduling errors gracefully' do
      allow(coordinator).to receive(:calculate_export_timing).and_raise(StandardError, 'Timing error')

      result = coordinator.schedule_export

      expect(result).to include(
        success: false,
        error: 'Timing error'
      )
    end
  end

  describe '#calculate_export_timing' do
    let(:coordinator) { described_class.new }
    let(:current_time) { Time.parse('2024-01-01 12:00:00 UTC') }
    let(:safety_margin) { 1.minute }

    before do
      allow(Time).to receive(:current).and_return(current_time)
    end

    context 'when export can be optimally scheduled' do
      it 'calculates optimal timing without TTL extension' do
        timing = coordinator.send(:calculate_export_timing, safety_margin)

        expect(timing).to include(
          needs_ttl_extension: false,
          scheduling_reason: 'optimal_timing'
        )
        expect(timing[:export_time]).to be < timing[:ttl_expiry_time]
      end
    end

    context 'when immediate export is needed' do
      let(:late_safety_margin) { 10.minutes } # Larger than retention window

      it 'calculates immediate export with TTL extension' do
        timing = coordinator.send(:calculate_export_timing, late_safety_margin)

        expect(timing).to include(
          needs_ttl_extension: true,
          scheduling_reason: 'immediate_with_ttl_extension'
        )
        expect(timing[:extension_duration]).to be > 0
      end
    end
  end

  describe '#execute_coordinated_export' do
    let(:coordinator) { described_class.new }
    let(:export_result) { { success: true, metrics: { counter1: { value: 42 } } } }

    before do
      allow(coordinator).to receive(:with_distributed_export_lock).and_yield
      allow(coordinator).to receive(:execute_export_with_recovery).and_return(export_result)
    end

    it 'executes export with distributed coordination' do
      result = coordinator.execute_coordinated_export(format: :json)

      expect(result).to eq(export_result)
    end

    it 'handles distributed lock timeout' do
      lock_error = described_class::DistributedLockTimeoutError.new('Lock timeout')
      allow(coordinator).to receive(:with_distributed_export_lock).and_raise(lock_error)

      result = coordinator.execute_coordinated_export(format: :prometheus)

      expect(result).to include(
        success: false,
        error: 'Export lock timeout - another container is exporting'
      )
    end

    it 'handles general export errors' do
      allow(coordinator).to receive(:with_distributed_export_lock).and_raise(StandardError, 'Export error')

      result = coordinator.execute_coordinated_export(format: :csv)

      expect(result).to include(
        success: false,
        error: 'Export error'
      )
    end
  end

  describe '#with_distributed_export_lock' do
    let(:coordinator) { described_class.new }
    let(:lock_key) { 'tasker:metrics:export_lock' }

    context 'when lock is successfully acquired' do
      before do
        allow(Rails.cache).to receive(:write).with(lock_key, coordinator.instance_id,
                                                   expires_in: 5.minutes, unless_exist: true).and_return(true)
        allow(Rails.cache).to receive(:delete).with(lock_key)
      end

      it 'executes block with lock' do
        executed = false
        coordinator.send(:with_distributed_export_lock) { executed = true }

        expect(executed).to be(true)
        expect(Rails.cache).to have_received(:delete).with(lock_key)
      end

      it 'releases lock even if block raises error' do
        expect do
          coordinator.send(:with_distributed_export_lock) { raise StandardError, 'Test error' }
        end.to raise_error(StandardError, 'Test error')

        expect(Rails.cache).to have_received(:delete).with(lock_key)
      end
    end

    context 'when lock cannot be acquired' do
      before do
        allow(Rails.cache).to receive(:write).with(lock_key, coordinator.instance_id,
                                                   expires_in: 5.minutes, unless_exist: true).and_return(false)
      end

      it 'raises DistributedLockTimeoutError' do
        expect do
          coordinator.send(:with_distributed_export_lock) {}
        end.to raise_error(described_class::DistributedLockTimeoutError)
      end
    end
  end

  describe '#execute_export_with_recovery' do
    let(:coordinator) { described_class.new }
    let(:successful_export) { { metrics: { counter1: { value: 42 } } } }

    before do
      allow(metrics_backend).to receive(:export_distributed_metrics).and_return(successful_export)
    end

    context 'when export succeeds on first attempt' do
      it 'returns successful result' do
        result = coordinator.send(:execute_export_with_recovery, :prometheus, false)

        expect(result).to include(
          success: true,
          format: :prometheus,
          attempts: 1,
          result: successful_export
        )
      end
    end

    context 'when export fails' do
      before do
        allow(metrics_backend).to receive(:export_distributed_metrics).and_raise(StandardError, 'Export failure')
        allow(coordinator).to receive(:extend_cache_ttl)
      end

      it 'extends cache TTL and re-raises error for job retry' do
        expect do
          coordinator.send(:execute_export_with_recovery, :prometheus, false)
        end.to raise_error(StandardError, 'Export failure')

        expect(coordinator).to have_received(:extend_cache_ttl).with(90.seconds) # 30s base + 60s safety margin
      end
    end
  end

  describe '#extend_cache_ttl' do
    let(:coordinator) { described_class.new }
    let(:extension_duration) { 2.minutes }
    let(:mock_metrics) do
      {
        'counter1' => { value: 10 },
        'gauge1' => { value: 25 }
      }
    end

    context 'when TTL extension is supported' do
      before do
        allow(coordinator).to receive(:ttl_extension_supported?).and_return(true)
        allow(metrics_backend).to receive(:all_metrics).and_return(mock_metrics)
        allow(metrics_backend).to receive(:send).with(:build_cache_key, anything).and_return('cache_key')
        allow(Rails.cache).to receive(:read).and_return({ data: 'test' })
        allow(Rails.cache).to receive(:write)
      end

      it 'extends TTL for all cached metrics' do
        result = coordinator.extend_cache_ttl(extension_duration)

        expect(result).to include(
          success: true,
          extension_duration: extension_duration,
          metrics_extended: 2
        )

        expect(Rails.cache).to have_received(:write).twice
      end
    end

    context 'when TTL extension is not supported' do
      before do
        allow(coordinator).to receive(:ttl_extension_supported?).and_return(false)
      end

      it 'returns failure with reason' do
        result = coordinator.extend_cache_ttl(extension_duration)

        expect(result).to include(
          success: false,
          reason: 'TTL extension not supported'
        )
      end
    end
  end

  describe '#ttl_extension_supported?' do
    let(:coordinator) { described_class.new }

    it 'returns true when cache has TTL inspection capability' do
      allow(coordinator).to receive(:detect_cache_capabilities).and_return({ ttl_inspection: true })

      expect(coordinator.send(:ttl_extension_supported?)).to be(true)
    end

    it 'returns true when cache has distributed capability' do
      allow(coordinator).to receive(:detect_cache_capabilities).and_return({ distributed: true })

      expect(coordinator.send(:ttl_extension_supported?)).to be(true)
    end

    it 'returns false when cache lacks both capabilities' do
      coordinator_with_limited_cache = described_class.new
      coordinator_with_limited_cache.instance_variable_set(:@cache_capabilities, { atomic_operations: true })

      expect(coordinator_with_limited_cache.send(:ttl_extension_supported?)).to be(false)
    end
  end

  describe 'instance identifier generation' do
    let(:coordinator) { described_class.new }

    it 'includes hostname, process ID, and timestamp' do
      allow(Socket).to receive(:gethostname).and_return('test-host')
      allow(Process).to receive(:pid).and_return(12_345)
      allow(Time).to receive(:current).and_return(Time.parse('2024-01-01 12:00:00 UTC'))

      instance_id = coordinator.send(:generate_instance_id)

      expect(instance_id).to eq('test-host-12345-1704110400')
    end

    it 'handles hostname resolution failure' do
      allow(Socket).to receive(:gethostname).and_raise(StandardError)
      allow(Process).to receive(:pid).and_return(12_345)

      instance_id = coordinator.send(:generate_instance_id)

      expect(instance_id).to include('unknown-12345-')
    end
  end

  describe 'structured logging' do
    let(:coordinator) { described_class.new }

    it 'logs coordinator initialization' do
      expect(coordinator).to receive(:log_structured).with(
        :info,
        'Export coordinator initialized',
        hash_including(
          instance_id: coordinator.instance_id,
          cache_capabilities: coordinator.cache_capabilities,
          config: coordinator.config
        )
      )

      coordinator.send(:log_coordinator_initialization)
    end

    it 'logs export scheduling' do
      format = :prometheus
      timing = { export_time: Time.current, scheduling_reason: 'optimal_timing' }
      job_result = { job_id: 'job-123' }

      expect(coordinator).to receive(:log_structured).with(
        :info,
        'Export scheduled',
        hash_including(
          format: format,
          export_time: timing[:export_time],
          scheduling_reason: timing[:scheduling_reason],
          job_id: job_result[:job_id]
        )
      )

      coordinator.send(:log_export_scheduled, format, timing, job_result)
    end
  end
end
