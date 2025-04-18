# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Instrumentation do
  let(:task_id) { 'task-123' }
  let(:task_name) { 'test_task' }
  let(:step_id) { 'step-456' }
  let(:step_name) { 'test_step' }

  # Create helper methods to fire different types of events
  def fire_task_start
    Tasker::LifecycleEvents.fire(
      Tasker::LifecycleEvents::Events::Task::START,
      { task_id: task_id, task_name: task_name }
    )
  end

  def fire_task_complete
    Tasker::LifecycleEvents.fire(
      Tasker::LifecycleEvents::Events::Task::COMPLETE,
      { task_id: task_id, task_name: task_name }
    )
  end

  def fire_step_handle
    Tasker::LifecycleEvents.fire(
      Tasker::LifecycleEvents::Events::Step::HANDLE,
      { task_id: task_id, step_id: step_id, step_name: step_name }
    )
  end

  context 'with subscriptions active' do
    let(:test_events) { [] }
    let(:subscription) { nil }

    before do
      # Add a test subscriber to capture all events
      ActiveSupport::Notifications.subscribe(/^tasker\./) do |name, started, finished, _id, payload|
        test_events << {
          name: name,
          duration: finished - started,
          payload: payload
        }
      end

      # Initialize the instrumentation
      described_class.subscribe
    end

    after do
      # Clean up subscription
      ActiveSupport::Notifications.unsubscribe(subscription) if subscription
      test_events.clear
    end

    it 'captures task lifecycle events' do
      expect(test_events.size).to eq(0)

      fire_task_start

      expect(test_events.size).to eq(1)
      expect(test_events.first[:name]).to eq("tasker.#{Tasker::LifecycleEvents::Events::Task::START}")
      expect(test_events.first[:payload][:task_id]).to eq(task_id)
      expect(test_events.first[:payload][:task_name]).to eq(task_name)
    end

    it 'captures step lifecycle events' do
      expect(test_events.size).to eq(0)

      fire_step_handle

      expect(test_events.size).to eq(1)
      expect(test_events.first[:name]).to eq("tasker.#{Tasker::LifecycleEvents::Events::Step::HANDLE}")
      expect(test_events.first[:payload][:task_id]).to eq(task_id)
      expect(test_events.first[:payload][:step_id]).to eq(step_id)
      expect(test_events.first[:payload][:step_name]).to eq(step_name)
    end

    it 'measures event duration' do
      # Fire an event with a sleep to ensure measurable duration
      Tasker::LifecycleEvents.fire('Slow.Event') { sleep(0.01) }

      expect(test_events.size).to eq(1)
      expect(test_events.first[:duration]).to be > 0.005
    end
  end

  describe 'OpenTelemetry integration', if: defined?(OpenTelemetry) do
    let(:mock_tracer) { instance_double(OpenTelemetry::Trace::Tracer) }
    let(:mock_span) do
      instance_double(OpenTelemetry::Trace::Span,
                      add_event: nil,
                      set_attribute: nil,
                      finish: nil,
                      context: instance_double(OpenTelemetry::Trace::SpanContext, hex_trace_id: 'trace-123'))
    end

    before do
      # Mock OpenTelemetry for testing
      allow(OpenTelemetry).to receive(:tracer_provider)
        .and_return(instance_double(
                      OpenTelemetry::SDK::Trace::TracerProvider, tracer: mock_tracer
                    ))
      allow(mock_tracer).to receive(:start_root_span).and_return(mock_span)
      allow(mock_tracer).to receive(:in_span).and_yield(mock_span)
      allow(OpenTelemetry::Trace).to receive(:current_span).and_return(mock_span)
      allow(OpenTelemetry::Trace).to receive(:context_with_span)
        .with(mock_span)
        .and_return(instance_double(OpenTelemetry::Context))
      allow(OpenTelemetry::Context).to receive(:with_current).and_yield

      # Initialize instrumentation
      described_class.subscribe
    end

    it 'creates spans for task events' do
      # Set up expectations with expect-receive
      expect(mock_tracer).to receive(:start_root_span)
        .with(Tasker::LifecycleEvents::Events::Task::START, hash_including(:attributes))
        .and_return(mock_span)
      expect(mock_span).to receive(:add_event)
        .with(Tasker::LifecycleEvents::Events::Task::START, anything)

      fire_task_start
    end

    it 'ends spans for task completion events' do
      # Set up expectations with expect-receive
      expect(mock_tracer).to receive(:start_root_span).and_return(mock_span)
      allow(mock_span).to receive(:status=)
      expect(mock_span).to receive(:finish)

      # First fire a start event to create the span
      fire_task_start
      fire_task_complete
    end

    it 'creates child spans for step events' do
      # First set up the task span
      allow(mock_tracer).to receive(:start_root_span).and_return(mock_span)

      # Set up expectation for child span
      expect(mock_tracer).to receive(:in_span)
        .with(Tasker::LifecycleEvents::Events::Step::HANDLE, anything)
        .and_yield(mock_span)

      # First fire a start event to create the span
      fire_task_start
      fire_step_handle
    end
  end

  describe '.convert_attributes' do
    it 'prefixes attribute keys with tasker.' do
      # Configure a service name for testing
      config = Tasker::Configuration.new
      config.otel_telemetry_service_name = 'test_service'
      allow(Tasker::Configuration).to receive(:configuration).and_return(config)

      # We'll use method_missing to access the private method for testing
      attributes = described_class.send(:convert_attributes, { key1: 'value1', key2: 'value2' })

      expect(attributes).to include('test_service.key1' => 'value1', 'test_service.key2' => 'value2')
    end

    it 'converts hashes and arrays to JSON strings' do
      attributes = described_class.send(:convert_attributes, {
                                          hash_value: { nested: 'data' },
                                          array_value: [1, 2, 3]
                                        })

      expect(attributes['tasker.hash_value']).to eq('{"nested":"data"}')
      expect(attributes['tasker.array_value']).to eq('[1,2,3]')
    end

    it 'handles nil values' do
      attributes = described_class.send(:convert_attributes, { nil_value: nil })

      expect(attributes['tasker.nil_value']).to eq('')
    end

    it 'skips exception_object' do
      exception = StandardError.new('Test error')
      attributes = described_class.send(:convert_attributes, {
                                          normal: 'value',
                                          exception_object: exception
                                        })

      expect(attributes).to include('tasker.normal' => 'value')
      expect(attributes).not_to include('tasker.exception_object')
    end
  end

  describe '.filter_sensitive_data' do
    before do
      # Reset configuration to default
      allow(Tasker::Configuration).to receive(:configuration).and_return(Tasker::Configuration.new)
    end

    it 'filters sensitive data based on configuration' do
      # Set up filter parameters
      config = Tasker::Configuration.configuration
      config.filter_parameters = [:password, 'credit_card.number', /secret/i]

      payload = {
        user: 'test_user',
        password: 'supersecret',
        credit_card: { number: '4242424242424242', name: 'Test User' },
        secret_key: 'api_key_12345',
        normal_data: 'visible'
      }

      # Filter the data
      filtered = described_class.send(:filter_sensitive_data, payload)

      # Verify filtering
      expect(filtered[:user]).to eq('test_user')
      expect(filtered[:password]).to eq('[FILTERED]')
      expect(filtered[:credit_card][:number]).to eq('[FILTERED]')
      expect(filtered[:credit_card][:name]).to eq('Test User')
      expect(filtered[:secret_key]).to eq('[FILTERED]')
      expect(filtered[:normal_data]).to eq('visible')
    end

    it 'uses custom mask when configured' do
      # Set up filter parameters with custom mask
      config = Tasker::Configuration.configuration
      config.filter_parameters = [:password]
      config.telemetry_filter_mask = '***REDACTED***'

      payload = { password: 'supersecret' }

      # Filter the data
      filtered = described_class.send(:filter_sensitive_data, payload)

      # Verify custom mask
      expect(filtered[:password]).to eq('***REDACTED***')
    end

    it 'preserves exception objects in the payload' do
      exception = StandardError.new('Test exception')

      payload = {
        user: 'test_user',
        exception_object: exception
      }

      # Filter the data
      filtered = described_class.send(:filter_sensitive_data, payload)

      # Verify exception object is preserved
      expect(filtered[:exception_object]).to eq(exception)
    end
  end
end
