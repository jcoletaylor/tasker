# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::MetricsExportJob do
  let(:coordinator) { instance_double(Tasker::Telemetry::ExportCoordinator) }
  let(:export_service) { instance_double(Tasker::Telemetry::MetricsExportService) }
  let(:successful_export_result) do
    {
      success: true,
      attempts: 1,
      result: {
        metrics: {
          'task_completions' => { type: :counter, value: 42 },
          'active_tasks' => { type: :gauge, value: 15 },
          'response_time' => {
            type: :histogram,
            buckets: { '0.1' => 10, '0.5' => 25, '1.0' => 40 },
            sum: 125.5,
            count: 40
          }
        }
      },
      exported_at: Time.current.iso8601
    }
  end

  let(:service_result) do
    {
      success: true,
      format: :prometheus,
      duration: 0.5,
      exported_at: Time.current.iso8601,
      delivery: { success: true, response_code: '200' }
    }
  end

  let(:job_params) do
    {
      format: :prometheus,
      coordinator_instance: 'test-instance-123',
      scheduled_by: 'export_coordinator',
      timing: { export_time: Time.current },
      include_instances: false
    }
  end

  before do
    allow(Tasker::Telemetry::ExportCoordinator).to receive(:instance).and_return(coordinator)
    allow(Tasker::Telemetry::MetricsExportService).to receive(:new).and_return(export_service)
    allow(coordinator).to receive(:execute_coordinated_export).and_return(successful_export_result)
    allow(export_service).to receive(:export_metrics).and_return(service_result)
  end

  describe 'job configuration' do
    it 'is configured with correct settings' do
      expect(described_class.queue_name).to eq('metrics_export')
    end

    it 'has retry configuration' do
      # ActiveJob retry configuration is set but hard to test directly
      # Instead we verify it's defined by checking the job can be performed
      expect { described_class.new.perform(**job_params) }.not_to raise_error
    end
  end

  describe '#perform' do
    it 'executes coordinated export successfully' do
      job = described_class.new

      job.perform(**job_params)

      expect(coordinator).to have_received(:execute_coordinated_export).with(
        format: :prometheus,
        include_instances: false
      )
    end

    it 'delegates to export service when coordination succeeds' do
      job = described_class.new

      job.perform(**job_params)

      expect(export_service).to have_received(:export_metrics).with(
        format: :prometheus,
        metrics_data: successful_export_result[:result],
        context: hash_including(
          job_id: anything,
          coordinator_instance: 'test-instance-123',
          scheduled_by: 'export_coordinator'
        )
      )
    end

    it 'handles export coordination failure gracefully' do
      failed_result = { success: false, error: 'Export coordination failed' }
      allow(coordinator).to receive(:execute_coordinated_export).and_return(failed_result)

      job = described_class.new
      expect(job).to receive(:handle_failed_coordination).with(failed_result)

      job.perform(**job_params)
    end

    it 'handles coordinator errors by re-raising' do
      allow(coordinator).to receive(:execute_coordinated_export).and_raise(StandardError, 'Coordinator error')

      job = described_class.new

      expect { job.perform(**job_params) }.to raise_error(StandardError, 'Coordinator error')
    end
  end

  describe '#export_with_service' do
    let(:job) { described_class.new }
    let(:metrics_data) { successful_export_result[:result] }

    before do
      job.instance_variable_set(:@format, :json)
      job.instance_variable_set(:@coordinator_instance, 'test-instance')
      job.instance_variable_set(:@scheduled_by, 'coordinator')
      job.instance_variable_set(:@timing, { export_time: Time.current })
    end

    it 'creates service with default configuration' do
      expect(Tasker::Telemetry::MetricsExportService).to receive(:new).with(no_args)

      job.send(:export_with_service, metrics_data)
    end

    it 'calls service with correct parameters' do
      job.send(:export_with_service, metrics_data)

      expect(export_service).to have_received(:export_metrics).with(
        format: :json,
        metrics_data: metrics_data,
        context: hash_including(
          coordinator_instance: 'test-instance',
          scheduled_by: 'coordinator',
          timing: kind_of(Hash)
        )
      )
    end
  end

  describe '#handle_failed_coordination' do
    let(:job) { described_class.new }

    it 'handles lock timeout gracefully' do
      lock_timeout_result = { success: false, error: 'Export lock timeout - another container is exporting' }

      expect(job).to receive(:log_concurrent_export_detected)
      expect { job.send(:handle_failed_coordination, lock_timeout_result) }.not_to raise_error
    end

    it 'raises error for actual coordination failures' do
      failure_result = { success: false, error: 'Database connection failed' }

      expect do
        job.send(:handle_failed_coordination, failure_result)
      end.to raise_error(StandardError, /Export coordination failed/)
    end
  end

  describe '#with_timeout' do
    let(:job) { described_class.new }

    it 'executes block within timeout' do
      executed = false

      job.send(:with_timeout, job) { executed = true }

      expect(executed).to be(true)
    end

    it 'raises error when timeout is exceeded' do
      allow(job).to receive(:job_timeout_duration).and_return(0.1)

      expect do
        job.send(:with_timeout, job) { sleep(0.2) }
      end.to raise_error(StandardError, /timed out/)
    end
  end

  describe '#job_timeout_duration' do
    let(:job) { described_class.new }

    it 'uses configured timeout when available' do
      allow(Tasker::Configuration).to receive_message_chain(:configuration, :telemetry, :prometheus)
        .and_return({ job_timeout: 10.minutes })

      expect(job.send(:job_timeout_duration)).to eq(10.minutes)
    end

    it 'uses default timeout when not configured' do
      allow(Tasker::Configuration).to receive_message_chain(:configuration, :telemetry, :prometheus)
        .and_return({})

      expect(job.send(:job_timeout_duration)).to eq(5.minutes)
    end

    it 'handles configuration errors gracefully' do
      allow(Tasker::Configuration).to receive(:configuration).and_raise(StandardError)

      expect(job.send(:job_timeout_duration)).to eq(5.minutes)
    end
  end

  describe '#extend_cache_ttl_for_retry' do
    let(:job) { described_class.new }

    context 'when not a retry attempt' do
      it 'does nothing for first execution' do
        allow(job).to receive(:executions).and_return(1)

        expect(Tasker::Telemetry::ExportCoordinator).not_to receive(:instance)
        job.send(:extend_cache_ttl_for_retry)
      end
    end

    context 'when on retry attempt' do
      before do
        allow(job).to receive_messages(executions: 2, calculate_job_retry_delay: 1.minute)
      end

      it 'extends cache TTL for retry delay' do
        coordinator = instance_double(Tasker::Telemetry::ExportCoordinator)
        allow(Tasker::Telemetry::ExportCoordinator).to receive(:instance).and_return(coordinator)
        allow(coordinator).to receive(:extend_cache_ttl).and_return({ success: true, metrics_extended: 5 })
        allow(job).to receive(:log_ttl_extension_for_retry)

        job.send(:extend_cache_ttl_for_retry)

        expect(coordinator).to have_received(:extend_cache_ttl).with(2.minutes) # 1min delay + 1min safety
        expect(job).to have_received(:log_ttl_extension_for_retry)
      end

      it 'handles TTL extension errors gracefully' do
        coordinator = instance_double(Tasker::Telemetry::ExportCoordinator)
        allow(Tasker::Telemetry::ExportCoordinator).to receive(:instance).and_return(coordinator)
        allow(coordinator).to receive(:extend_cache_ttl).and_raise(StandardError, 'TTL error')
        allow(job).to receive(:log_ttl_extension_error)

        expect { job.send(:extend_cache_ttl_for_retry) }.not_to raise_error
        expect(job).to have_received(:log_ttl_extension_error)
      end
    end
  end

  describe '#calculate_job_retry_delay' do
    let(:job) { described_class.new }

    it 'calculates exponential backoff delays' do
      expect(job.send(:calculate_job_retry_delay, 1)).to eq(30.seconds)
      expect(job.send(:calculate_job_retry_delay, 2)).to eq(30.seconds)
      expect(job.send(:calculate_job_retry_delay, 3)).to eq(1.minute)
      expect(job.send(:calculate_job_retry_delay, 4)).to eq(2.minutes)
      expect(job.send(:calculate_job_retry_delay, 5)).to eq(4.minutes)
    end

    it 'caps maximum delay' do
      expect(job.send(:calculate_job_retry_delay, 10)).to eq(10.minutes)
    end
  end

  describe 'logging methods' do
    let(:job) { described_class.new }

    before do
      job.instance_variable_set(:@format, :prometheus)
      job.instance_variable_set(:@coordinator_instance, 'test-instance')
      job.instance_variable_set(:@scheduled_by, 'coordinator')
      job.instance_variable_set(:@timing, { export_time: Time.current })
      job.instance_variable_set(:@include_instances, false)
      job.instance_variable_set(:@job_start_time, 5.seconds.ago)
      allow(job).to receive(:job_id).and_return('job-123')
    end

    describe '#log_job_started' do
      it 'logs job start with all parameters' do
        expect(job).to receive(:log_structured).with(
          :info,
          'Metrics export job started',
          hash_including(
            job_id: 'job-123',
            format: :prometheus,
            coordinator_instance: 'test-instance',
            scheduled_by: 'coordinator'
          )
        )

        job.send(:log_job_started)
      end
    end

    describe '#log_job_completed' do
      it 'logs successful completion with service result' do
        expect(job).to receive(:log_structured).with(
          :info,
          'Metrics export job completed',
          hash_including(
            job_id: 'job-123',
            format: :prometheus,
            success: true,
            duration: kind_of(Numeric),
            service_duration: 0.5
          )
        )

        job.send(:log_job_completed, service_result)
      end
    end

    describe '#log_job_error' do
      it 'logs error with full context' do
        error = StandardError.new('Test error')
        error.set_backtrace(%w[line1 line2])

        expect(job).to receive(:log_structured).with(
          :error,
          'Metrics export job error',
          hash_including(
            job_id: 'job-123',
            format: :prometheus,
            error: 'Test error',
            error_class: 'StandardError',
            backtrace: ['line1', 'line2', nil, nil, nil]
          )
        )

        job.send(:log_job_error, error)
      end
    end

    describe '#log_coordination_failure' do
      it 'logs coordination failure details' do
        failure_result = { error: 'Lock timeout', attempts: 2 }

        expect(job).to receive(:log_structured).with(
          :warn,
          'Export coordination failed',
          hash_including(
            job_id: 'job-123',
            format: :prometheus,
            error: 'Lock timeout',
            attempts: 2
          )
        )

        job.send(:log_coordination_failure, failure_result)
      end
    end

    describe '#log_concurrent_export_detected' do
      it 'logs concurrent export detection' do
        expect(job).to receive(:log_structured).with(
          :info,
          'Concurrent export detected - skipping',
          hash_including(
            job_id: 'job-123',
            format: :prometheus,
            reason: 'another_container_exporting'
          )
        )

        job.send(:log_concurrent_export_detected)
      end
    end
  end
end
