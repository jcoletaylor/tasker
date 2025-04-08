# frozen_string_literal: true

require 'rails_helper'
require_relative 'memory_adapter'
require_relative '../../../support/telemetry_test_helper'

RSpec.describe 'Telemetry Integration' do
  include TelemetryTestHelper

  # Create a real task
  let(:task_request) { Tasker::Types::TaskRequest.new(name: 'test_task', context: { test: true }) }
  let(:task) { Tasker::Task.create_with_defaults!(task_request) }
  let(:memory_adapter) { MemoryAdapter.new }

  before do
    # Reset all singletons
    Tasker::Telemetry.reset_adapters!
    Tasker::LifecycleEvents.reset_observers
    Tasker::Telemetry::Observer.reset_instance

    # Initialize telemetry (which registers the observer)
    Tasker::Telemetry.initialize
  end

  it 'records events fired through lifecycle events' do
    with_isolated_telemetry(memory_adapter) do
      original_event_count = memory_adapter.recorded_events.size
      # Fire an event
      Tasker::LifecycleEvents.fire('test.event', { task_id: task.task_id })

      # Verify the adapter received the event
      expect(memory_adapter.recorded_events.size).to be > original_event_count
      expect(memory_adapter.recorded_events.first[:event]).to eq('test.event')
      expect(memory_adapter.recorded_events.first[:payload][:task_id]).to eq(task.task_id)
    end
  end

  it 'creates spans for blocks executed through lifecycle events' do
    with_isolated_telemetry(memory_adapter) do
      original_event_count = memory_adapter.recorded_events.size
      original_span_count = memory_adapter.spans.size
      # Fire an event with a span
      result = Tasker::LifecycleEvents.fire_with_span('test.span', { task_id: task.task_id }) { 42 }

      # Verify the result
      expect(result).to eq(42)

      # Verify the adapter recorded the event
      expect(memory_adapter.recorded_events.size).to be > original_event_count

      # Verify a span was created
      expect(memory_adapter.spans.size).to be > original_span_count
      expect(memory_adapter.spans.first[:name]).to eq('test.span')
    end
  end
end
