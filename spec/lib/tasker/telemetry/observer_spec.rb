# frozen_string_literal: true

require 'rails_helper'
require_relative 'memory_adapter'
require_relative '../../../support/telemetry_test_helper'

RSpec.describe Tasker::Telemetry::Observer do
  include TelemetryTestHelper

  # Create a real memory adapter for verification
  let(:memory_adapter) { MemoryAdapter.new }
  let(:observer) { described_class.new }
  let(:event) { 'test.event' }
  let(:context) { { key: 'value', dummy: true } }
  let(:task_request) { Tasker::Types::TaskRequest.new(name: 'test_task', context: context) }
  let(:task) { Tasker::Task.create_with_defaults!(task_request) }

  after do
    memory_adapter.clear
  end

  describe '#initialize' do
    it 'registers itself with the lifecycle events system' do
      with_isolated_telemetry(memory_adapter) do
        # Create a new observer in the isolated environment
        test_observer = described_class.new

        # Verify it's registered
        expect(Tasker::LifecycleEvents.observers).to include(test_observer)
      end
    end
  end

  describe '#on_lifecycle_event' do
    it 'records the event with telemetry' do
      with_isolated_telemetry(memory_adapter) do
        # Manually call the method
        observer.on_lifecycle_event(event, context)

        # Verify the event was recorded
        expect(memory_adapter.recorded_events.size).to eq(1)
        expect(memory_adapter.recorded_events.first[:event]).to eq(event)
        expect(memory_adapter.recorded_events.first[:payload]).to eq(context)
      end
    end
  end

  describe 'integration with lifecycle events' do
    it 'processes events fired through lifecycle events' do
      with_isolated_telemetry(memory_adapter) do
        # Register our observer - not needed with with_isolated_telemetry as it already creates an observer
        # Tasker::LifecycleEvents.register_observer(observer)

        # Fire an event
        Tasker::LifecycleEvents.fire(event, context)

        # Verify the event was handled
        expect(memory_adapter.recorded_events.size).to eq(1)
        expect(memory_adapter.recorded_events.first[:event]).to eq(event)
      end
    end

    it 'creates spans for blocks when events are fired with spans' do
      with_isolated_telemetry(memory_adapter) do
        # Register our observer - not needed with with_isolated_telemetry as it already creates an observer
        # Tasker::LifecycleEvents.register_observer(observer)

        # Fire an event with a span
        result = Tasker::LifecycleEvents.fire_with_span(event, context) { 42 }

        # Verify the correct result
        expect(result).to eq(42)

        # Verify the span was created
        expect(memory_adapter.spans.size).to eq(1)
        expect(memory_adapter.spans.first[:name]).to eq(event)
      end
    end
  end

  describe '#start_task_trace' do
    it 'starts a trace for the task' do
      with_isolated_telemetry(memory_adapter) do
        # Call the method
        observer.start_task_trace(task)

        # Verify a trace was started
        expect(memory_adapter.traces.size).to eq(1)
        expect(memory_adapter.traces.first[:name]).to eq('task.test_task')
      end
    end
  end

  describe '#end_task_trace' do
    it 'ends the current trace' do
      with_isolated_telemetry(memory_adapter) do
        # Start a trace first
        observer.start_task_trace(task)

        # Then end it
        observer.end_task_trace

        # Verify the trace was ended (check if ended_at was set)
        expect(memory_adapter.traces.first[:ended_at]).not_to be_nil
      end
    end
  end
end
