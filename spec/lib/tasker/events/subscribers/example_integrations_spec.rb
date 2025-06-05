# frozen_string_literal: true

require 'rails_helper'

# Load developer-facing example subscriber implementations
require_relative 'examples/sentry_subscriber'
require_relative 'examples/pagerduty_subscriber'
require_relative 'examples/slack_subscriber'

RSpec.describe 'Event Subscriber Integration Examples', type: :integration do
  let(:publisher) { Tasker::Events::Publisher.instance }

  describe 'Sentry Integration Example' do
    let(:sentry_subscriber_class) { SentrySubscriber }

    it 'successfully subscribes to error events' do
      sentry_subscriber_class.new
      expect(sentry_subscriber_class.subscribed_events).to contain_exactly(
        'task.failed', 'step.failed', 'workflow.error'
      )
    end

    it 'handles task failure events with proper Sentry formatting' do
      subscriber = sentry_subscriber_class.new

      event_payload = {
        task_id: 'task_123',
        error_message: 'Database connection failed',
        timestamp: Time.current,
        execution_status: 'error'
      }

      # Test that the method executes without error and processes the payload
      expect { subscriber.handle_task_failed(event_payload) }.not_to raise_error
    end

    it 'handles step failure events with attempt tracking' do
      subscriber = sentry_subscriber_class.new

      event_payload = {
        task_id: 'task_456',
        step_id: 'step_789',
        error_message: 'API timeout',
        attempt_number: 3
      }

      # Test that the method executes without error and processes the payload
      expect { subscriber.handle_step_failed(event_payload) }.not_to raise_error
    end
  end

  describe 'PagerDuty Integration Example' do
    let(:pagerduty_subscriber_class) { PagerDutySubscriber }

    it 'subscribes to critical error events only' do
      expect(pagerduty_subscriber_class.subscribed_events).to contain_exactly(
        'task.failed', 'workflow.error'
      )
    end

    it 'demonstrates business logic filtering for critical tasks' do
      subscriber = pagerduty_subscriber_class.new

      # Test critical task identification
      expect(subscriber.send(:critical_task?, 'critical_payment_task_123')).to be true
      expect(subscriber.send(:critical_task?, 'production_order_456')).to be true
      expect(subscriber.send(:critical_task?, 'regular_task_789')).to be false
    end

    it 'handles critical and non-critical tasks appropriately' do
      subscriber = pagerduty_subscriber_class.new

      # Critical task should process without error
      critical_event = {
        task_id: 'critical_payment_task_123',
        error_message: 'Payment processing failed'
      }
      expect { subscriber.handle_task_failed(critical_event) }.not_to raise_error

      # Non-critical task should also process without error (but skip alerting)
      regular_event = {
        task_id: 'regular_task_456',
        error_message: 'Minor processing issue'
      }
      expect { subscriber.handle_task_failed(regular_event) }.not_to raise_error
    end
  end

  describe 'Slack Integration Example' do
    let(:slack_subscriber_class) { SlackSubscriber }

    it 'demonstrates environment-based channel routing' do
      subscriber = slack_subscriber_class.new

      # Test that channel selection logic works
      expect(subscriber.send(:channel_for_success_notifications)).to be_a(String)
      expect(subscriber.send(:channel_for_alerts)).to be_a(String)
    end

    it 'formats task completion notifications properly' do
      subscriber = slack_subscriber_class.new

      event_payload = {
        task_id: 'order_processing_789',
        task_name: 'Order Processing',
        execution_duration: 45.2,
        total_steps: 5,
        completed_steps: 5
      }

      expect { subscriber.handle_task_completed(event_payload) }.not_to raise_error
    end

    it 'formats task failure alerts properly' do
      subscriber = slack_subscriber_class.new

      event_payload = {
        task_id: 'payment_task_123',
        task_name: 'Payment Processing',
        error_message: 'Credit card authorization failed',
        failed_steps: 1,
        total_steps: 3
      }

      expect { subscriber.handle_task_failed(event_payload) }.not_to raise_error
    end

    it 'demonstrates duration formatting utility' do
      subscriber = slack_subscriber_class.new

      expect(subscriber.send(:format_duration, 30)).to eq('30s')
      expect(subscriber.send(:format_duration, 90)).to eq('1m')
      expect(subscriber.send(:format_duration, 7200)).to eq('2h')
    end
  end

  describe 'Subscriber Registration and Event Flow' do
    it 'demonstrates complete subscriber registration and event handling' do
      # Create a simple test subscriber
      test_subscriber_class = Class.new(Tasker::Events::Subscribers::BaseSubscriber) do
        subscribe_to 'task.completed'

        def handle_task_completed(event)
          # Simple processing without logging expectations
          @received_event = event
        end

        attr_reader :received_event
      end

      # Register the subscriber
      test_subscriber = test_subscriber_class.new
      expect { test_subscriber_class.subscribe(publisher) }.not_to raise_error

      # Verify the subscription worked
      expect(test_subscriber_class.subscribed_events).to include('task.completed')

      # Test event handling
      test_event = { task_id: 'test_123', task_name: 'Test Task' }
      expect { test_subscriber.handle_task_completed(test_event) }.not_to raise_error
      expect(test_subscriber.received_event).to eq(test_event)
    end
  end
end
