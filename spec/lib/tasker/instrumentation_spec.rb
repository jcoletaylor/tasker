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
      Tasker::LifecycleEvents.fire('slow.event') { sleep(0.01) }

      expect(test_events.size).to eq(1)
      expect(test_events.first[:duration]).to be > 0.005
    end
  end

  describe 'OpenTelemetry integration', if: defined?(OpenTelemetry) do
    let(:mock_tracer) { double('OpenTelemetry::Tracer') }
    let(:mock_span) do
      double('OpenTelemetry::Span', add_event: nil, set_attribute: nil, finish: nil,
                                    status: nil, context: double('SpanContext', hex_trace_id: 'trace-123'))
    end

    before do
      # Mock OpenTelemetry for testing
      allow(OpenTelemetry).to receive(:tracer_provider).and_return(double('TracerProvider', tracer: mock_tracer))
      allow(mock_tracer).to receive(:start_root_span).and_return(mock_span)
      allow(mock_tracer).to receive(:in_span).and_yield(mock_span)
      allow(OpenTelemetry::Trace).to receive(:current_span).and_return(mock_span)
      allow(OpenTelemetry::Trace).to receive(:context_with_span).with(mock_span).and_return(double('Context'))
      allow(OpenTelemetry::Context).to receive(:with_current).and_yield

      # Initialize instrumentation
      described_class.subscribe
    end

    it 'creates spans for task events' do
      # We expect a span to be created with attributes
      expect(mock_tracer).to receive(:start_root_span)
        .with(Tasker::LifecycleEvents::Events::Task::START, hash_including(:attributes))
        .and_return(mock_span)
      expect(mock_span).to receive(:add_event).with(Tasker::LifecycleEvents::Events::Task::START, anything)

      fire_task_start
    end

    it 'ends spans for task completion events' do
      # Set up appropriate mock expectations
      allow(mock_tracer).to receive(:start_root_span).and_return(mock_span)

      # For the finish behavior
      allow(mock_span).to receive(:status=)
      expect(mock_span).to receive(:finish)

      # First fire a start event to create the span
      fire_task_start

      fire_task_complete
    end

    it 'creates child spans for step events' do
      # First fire a start event to create the parent span
      fire_task_start

      # We expect a child span to be created
      expect(mock_tracer).to receive(:in_span)
        .with(Tasker::LifecycleEvents::Events::Step::HANDLE, anything)
        .and_yield(mock_span)

      fire_step_handle
    end
  end

  describe '.convert_attributes' do
    it 'prefixes attribute keys with tasker.' do
      # We'll use method_missing to access the private method for testing
      attributes = described_class.send(:convert_attributes, { key1: 'value1', key2: 'value2' })

      expect(attributes).to include('tasker.key1' => 'value1', 'tasker.key2' => 'value2')
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
end
