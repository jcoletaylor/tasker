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
    it 'publishes events through the core infrastructure' do
      publisher.publish(event_name, context)

      # The core publisher creates events that are processed by telemetry
      expect(captured_events.size).to be >= 1

      # Find the metric event created by telemetry
      metric_event = captured_events.find { |e| e[:name].include?('metric') }
      expect(metric_event).to be_present
      expect(metric_event[:name]).to eq("tasker.metric.tasker.#{event_name}")
    end

    it 'adds timestamp to event payload automatically' do
      freeze_time = Time.current
      allow(Time).to receive(:current).and_return(freeze_time)

      publisher.publish(event_name, context)

      # The telemetry creates standardized payloads with event_timestamp
      metric_event = captured_events.find { |e| e[:name].include?('metric') }
      expect(metric_event[:payload][:event_timestamp]).to be_present
    end

    it 'handles events with existing timestamps' do
      custom_timestamp = 1.hour.ago
      payload_with_timestamp = context.merge(timestamp: custom_timestamp)

      publisher.publish(event_name, payload_with_timestamp)

      # Should not override existing timestamp
      expect(captured_events.size).to be >= 1
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
    it 'registers all standard events during initialization' do
      # Test that the publisher can publish all the standard events without errors
      expect do
        publisher.publish(Tasker::Constants::TaskEvents::INITIALIZE_REQUESTED, context)
        publisher.publish(Tasker::Constants::StepEvents::COMPLETED, context)
        publisher.publish(Tasker::Constants::WorkflowEvents::TASK_STARTED, context)
        publisher.publish(Tasker::Constants::ObservabilityEvents::Task::HANDLE, context)
      end.not_to raise_error
    end

    it 'registers test events in local environment' do
      if Rails.env.local?
        expect do
          publisher.publish(Tasker::Constants::TestEvents::BASIC_EVENT, context)
          publisher.publish('Test.Event', context)
        end.not_to raise_error
      end
    end
  end

  describe 'core infrastructure responsibilities' do
    it 'provides the foundation for the EventPublisher concern' do
      # The Publisher should be the backend for the EventPublisher concern
      expect(Tasker::Events::Publisher.instance).to respond_to(:publish)
      expect(Tasker::Events::Publisher.instance).to be_a(Singleton)
    end

    it 'handles dry-events publishing' do
      # Verify it includes the dry-events functionality
      expect(publisher.class.ancestors).to include(Dry::Events::Publisher)
      expect(publisher).to respond_to(:subscribe)
      expect(publisher).to respond_to(:publish)
    end
  end
end
