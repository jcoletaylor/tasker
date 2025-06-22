# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Concerns::StructuredLogging, type: :concern do
  # Create a test class that includes the concern
  let(:test_class) do
    Class.new do
      include Tasker::Concerns::StructuredLogging

      def self.name
        'TestComponent'
      end
    end
  end

  let(:test_instance) { test_class.new }
  let(:captured_logs) { [] }

  # Mock Rails logger to capture log output
  before do
    allow(Rails.logger).to receive(:info) { |message| captured_logs << { level: :info, message: message } }
    allow(Rails.logger).to receive(:debug) { |message| captured_logs << { level: :debug, message: message } }
    allow(Rails.logger).to receive(:warn) { |message| captured_logs << { level: :warn, message: message } }
    allow(Rails.logger).to receive(:error) { |message| captured_logs << { level: :error, message: message } }
  end

  after do
    # Clean up thread-local storage
    Thread.current[described_class::CORRELATION_ID_KEY] = nil
  end

  describe '#correlation_id' do
    it 'generates a correlation ID if none exists' do
      expect(test_instance.correlation_id).to match(/\Atsk_[a-z0-9]+_[A-Za-z0-9]+\z/)
    end

    it 'returns the same correlation ID for multiple calls' do
      first_id = test_instance.correlation_id
      second_id = test_instance.correlation_id

      expect(first_id).to eq(second_id)
    end

    it 'allows setting a custom correlation ID' do
      test_instance.correlation_id = 'custom_id_123'
      expect(test_instance.correlation_id).to eq('custom_id_123')
    end
  end

  describe '#with_correlation_id' do
    it 'temporarily sets correlation ID for block execution' do
      original_id = test_instance.correlation_id

      result = test_instance.with_correlation_id('temp_id') do
        expect(test_instance.correlation_id).to eq('temp_id')
        'block_result'
      end

      expect(result).to eq('block_result')
      expect(test_instance.correlation_id).to eq(original_id)
    end
  end

  describe '#log_structured' do
    it 'logs with JSON format by default' do
      test_instance.log_structured(:info, 'Test message', key: 'value')

      expect(captured_logs.size).to eq(1)
      log_entry = captured_logs.first

      expect(log_entry[:level]).to eq(:info)

      # Parse the JSON to verify structure
      parsed = JSON.parse(log_entry[:message])
      expect(parsed['message']).to eq('Test message')
      expect(parsed['key']).to eq('value')
      expect(parsed['correlation_id']).to be_present
      expect(parsed['timestamp']).to be_present
      expect(parsed['component']).to eq('test_component')
    end

    it 'includes standard context fields' do
      test_instance.log_structured(:info, 'Test message')

      parsed = JSON.parse(captured_logs.first[:message])
      expect(parsed['environment']).to eq(Rails.env)
      expect(parsed['tasker_version']).to eq(Tasker::VERSION)
      expect(parsed['process_id']).to be_present
      expect(parsed['thread_id']).to be_present
    end

    context 'with different log level configuration' do
      let(:original_config) { Tasker.configuration.telemetry }
      let(:new_config) do
        original_config.class.new(
          original_config.to_h.merge(log_level: 'warn')
        )
      end

      before do
        allow(Tasker.configuration).to receive(:telemetry).and_return(new_config)
      end

      after do
        allow(Tasker.configuration).to receive(:telemetry).and_return(original_config)
      end

      it 'respects log level configuration' do
        test_instance.log_structured(:debug, 'Debug message')
        test_instance.log_structured(:info, 'Info message')
        test_instance.log_structured(:warn, 'Warning message')

        expect(captured_logs.size).to eq(1)
        parsed = JSON.parse(captured_logs.first[:message])
        expect(parsed['message']).to eq('Warning message')
      end
    end
  end

  describe '#log_task_event' do
    let(:task) { double('Task', task_id: 'task_123', name: 'test_task', status: 'pending') }

    it 'logs task events with standardized format' do
      test_instance.log_task_event(task, :started, priority: 'high')

      parsed = JSON.parse(captured_logs.first[:message])
      expect(parsed['message']).to eq('Task started')
      expect(parsed['entity_type']).to eq('task')
      expect(parsed['entity_id']).to eq('task_123')
      expect(parsed['entity_name']).to eq('test_task')
      expect(parsed['event_type']).to eq('started')
      expect(parsed['task_status']).to eq('pending')
      expect(parsed['priority']).to eq('high')
    end
  end

  describe '#log_step_event' do
    let(:task) { double('Task', task_id: 'task_123', name: 'test_task') }
    let(:step) do
      double('Step',
             workflow_step_id: 'step_456',
             name: 'test_step',
             status: 'complete',
             task: task)
    end

    it 'logs step events with performance data' do
      test_instance.log_step_event(step, :completed, duration: 2.5, records_processed: 100)

      parsed = JSON.parse(captured_logs.first[:message])
      expect(parsed['message']).to eq('Step completed')
      expect(parsed['entity_type']).to eq('step')
      expect(parsed['entity_id']).to eq('step_456')
      expect(parsed['entity_name']).to eq('test_step')
      expect(parsed['task_id']).to eq('task_123')
      expect(parsed['duration_ms']).to eq(2500.0)
      expect(parsed['performance_category']).to eq('slow')
      expect(parsed['records_processed']).to eq(100)
    end
  end

  describe '#log_performance_event' do
    context 'with debug logging enabled' do
      let(:original_config) { Tasker.configuration.telemetry }
      let(:debug_config) do
        original_config.class.new(
          original_config.to_h.merge(log_level: 'debug')
        )
      end

      before do
        allow(Tasker.configuration).to receive(:telemetry).and_return(debug_config)
      end

      after do
        allow(Tasker.configuration).to receive(:telemetry).and_return(original_config)
      end

      it 'logs performance events with timing categorization' do
        test_instance.log_performance_event('sql_query', 0.05, table: 'users')

        expect(captured_logs.size).to eq(1)
        parsed = JSON.parse(captured_logs.first[:message])
        expect(parsed['message']).to eq('Performance measurement')
        expect(parsed['entity_type']).to eq('performance')
        expect(parsed['operation']).to eq('sql_query')
        expect(parsed['duration_ms']).to eq(50.0)
        expect(parsed['performance_category']).to eq('fast')
        expect(parsed['is_slow']).to be_falsey
        expect(parsed['table']).to eq('users')
      end
    end

    context 'with custom slow threshold configuration' do
      let(:original_config) { Tasker.configuration.telemetry }
      let(:slow_threshold_config) do
        original_config.class.new(
          original_config.to_h.merge(
            log_level: 'debug',
            slow_query_threshold_seconds: 0.5
          )
        )
      end

      before do
        allow(Tasker.configuration).to receive(:telemetry).and_return(slow_threshold_config)
      end

      after do
        allow(Tasker.configuration).to receive(:telemetry).and_return(original_config)
      end

      it 'marks slow operations appropriately' do
        test_instance.log_performance_event('slow_operation', 1.2)

        expect(captured_logs.size).to eq(1)
        parsed = JSON.parse(captured_logs.first[:message])
        expect(parsed['is_slow']).to be_truthy
        expect(parsed['performance_category']).to eq('slow')

        # Should log at warn level for slow operations
        expect(captured_logs.first[:level]).to eq(:warn)
      end
    end
  end

  describe '#log_exception' do
    let(:exception) { StandardError.new('Something went wrong') }

    before do
      # Mock backtrace
      allow(exception).to receive(:backtrace).and_return([
                                                           '/app/lib/tasker/something.rb:123:in `method`',
                                                           '/gems/some-gem/lib/gem.rb:456:in `gem_method`',
                                                           '/app/controllers/test_controller.rb:789:in `action`'
                                                         ])
    end

    it 'logs exceptions with structured format' do
      test_instance.log_exception(exception, context: { operation: 'task_processing' })

      parsed = JSON.parse(captured_logs.first[:message])
      expect(parsed['message']).to eq('Exception occurred: StandardError')
      expect(parsed['entity_type']).to eq('exception')
      expect(parsed['exception_class']).to eq('StandardError')
      expect(parsed['exception_message']).to eq('Something went wrong')
      expect(parsed['operation']).to eq('task_processing')
      expect(parsed['backtrace']).to be_an(Array)
      expect(parsed['backtrace']).to include('/app/lib/tasker/something.rb:123:in `method`')
    end
  end

  describe 'correlation ID generation' do
    it 'generates unique IDs for different instances' do
      # Clear any existing correlation IDs to ensure fresh generation
      Thread.current[described_class::CORRELATION_ID_KEY] = nil

      instance1 = test_class.new
      instance2 = test_class.new

      # Generate IDs in sequence with time difference to ensure uniqueness
      id1 = instance1.correlation_id
      sleep(0.001) # Small delay to ensure timestamp difference
      Thread.current[described_class::CORRELATION_ID_KEY] = nil # Clear for second instance
      id2 = instance2.correlation_id

      expect(id1).not_to eq(id2)
      expect(id1).to match(/\Atsk_[a-z0-9]+_[A-Za-z0-9]+\z/)
      expect(id2).to match(/\Atsk_[a-z0-9]+_[A-Za-z0-9]+\z/)
    end
  end

  describe 'parameter filtering' do
    context 'with parameter filtering enabled' do
      let(:original_config) { Tasker.configuration.telemetry }
      let(:filtered_config) do
        original_config.class.new(
          original_config.to_h.merge(filter_parameters: %i[password token])
        )
      end

      before do
        allow(Tasker.configuration).to receive(:telemetry).and_return(filtered_config)
      end

      after do
        allow(Tasker.configuration).to receive(:telemetry).and_return(original_config)
      end

      it 'filters sensitive parameters from logs' do
        test_instance.log_structured(:info, 'Login attempt', password: 'secret', token: 'abc123')

        parsed = JSON.parse(captured_logs.first[:message])
        expect(parsed['password']).to eq('[FILTERED]')
        expect(parsed['token']).to eq('[FILTERED]')
      end
    end
  end
end
