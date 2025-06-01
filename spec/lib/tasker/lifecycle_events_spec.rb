# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Events::Publisher do
  let(:publisher) { described_class.instance }
  let(:event_name) { Tasker::Constants::TaskEvents::START_REQUESTED }
  let(:context) { { task_id: 123, task_name: 'test_task' } }

  let(:captured_events) { [] }
  let(:subscription) { nil }

  before do
    # Create a subscription to capture events
    ActiveSupport::Notifications.subscribe(/^tasker\./) do |name, started, finished, id, payload|
      captured_events << {
        name: name,
        started: started,
        finished: finished,
        id: id,
        payload: payload
      }
    end
  end

  after do
    # Clean up subscription
    ActiveSupport::Notifications.unsubscribe(subscription) if subscription
    captured_events.clear
  end

  describe '#publish' do
    it 'publishes events through the unified publisher' do
      publisher.publish(event_name, context)

      # The unified event system creates metric events through telemetry
      expect(captured_events.size).to be >= 1

      # Find the metric event created by telemetry
      metric_event = captured_events.find { |e| e[:name].include?('metric') }
      expect(metric_event).to be_present
      expect(metric_event[:name]).to eq("tasker.metric.tasker.#{event_name}")
    end

    it 'adds timestamp to event payload' do
      freeze_time = Time.current
      allow(Time).to receive(:current).and_return(freeze_time)

      publisher.publish(event_name, context)

      # The telemetry creates standardized payloads with event_timestamp
      metric_event = captured_events.find { |e| e[:name].include?('metric') }
      expect(metric_event[:payload][:event_timestamp]).to be_present
    end
  end

  describe '#publish_task_event' do
    let(:task) { double('Task', task_id: 123, name: 'test_task', status: 'pending') }

    it 'publishes task events with standardized payload' do
      publisher.publish_task_event(event_name, task, { additional: 'data' })

      # The telemetry system creates standardized payloads through TelemetrySubscriber
      expect(captured_events.size).to be >= 1

      # Find the metric event created by telemetry
      metric_event = captured_events.find { |e| e[:name].include?('metric') }
      expect(metric_event).to be_present
      expect(metric_event[:payload]).to include(
        task_name: 'unknown_task', # TelemetrySubscriber provides default when task name not in expected format
        event_timestamp: be_present
      )
    end
  end

  describe '#publish_step_event' do
    let(:step) { double('Step', workflow_step_id: 456, name: 'test_step', task_id: 123, status: 'pending') }

    it 'publishes step events with standardized payload' do
      publisher.publish_step_event(Tasker::Constants::StepEvents::COMPLETED, step, { additional: 'data' })

      # The telemetry system creates standardized payloads with EventPayloadBuilder integration
      expect(captured_events.size).to be >= 1

      # Find the metric event created by telemetry
      metric_event = captured_events.find { |e| e[:name].include?('metric') }
      expect(metric_event).to be_present
      expect(metric_event[:payload]).to include(
        step_name: 'unknown_step', # TelemetrySubscriber provides default
        event_timestamp: be_present,
        execution_duration: be_present, # EventPayloadBuilder adds this
        attempt_number: be_present      # EventPayloadBuilder adds this
      )
    end
  end

  describe 'singleton behavior' do
    it 'returns the same instance' do
      instance1 = described_class.instance
      instance2 = described_class.instance

      expect(instance1).to be(instance2)
    end

    it 'prevents direct instantiation' do
      expect { described_class.new }.to raise_error(NoMethodError)
    end
  end

  describe 'event registration' do
    it 'registers all events during initialization' do
      # Test that the publisher can publish all the standard events without errors
      expect do
        publisher.publish(Tasker::Constants::TaskEvents::INITIALIZE_REQUESTED, context)
        publisher.publish(Tasker::Constants::StepEvents::COMPLETED, context)
        publisher.publish(Tasker::Constants::WorkflowEvents::TASK_STARTED, context)
        publisher.publish(Tasker::Constants::ObservabilityEvents::Task::HANDLE, context)
      end.not_to raise_error
    end
  end
end
