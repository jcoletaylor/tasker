# frozen_string_literal: true

# Helper module for isolated telemetry testing
module TelemetryTestHelper
  # Setup isolated telemetry for a test
  def with_isolated_telemetry
    test_events = []
    test_spans = []

    # Store original subscribers
    original_subscribers = ActiveSupport::Notifications.notifier.listeners_for(/^tasker\./).dup

    # Remove existing subscribers
    original_subscribers.each do |subscriber|
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    # Add a test subscriber
    subscription = ActiveSupport::Notifications.subscribe(/^tasker\./) do |name, started, finished, _unique_id, payload|
      test_events << {
        name: name,
        duration: finished - started,
        payload: payload
      }
    end

    # Create a test adapter for tracking spans
    test_adapter = Object.new
    test_adapter.define_singleton_method(:recorded_events) { test_events }
    test_adapter.define_singleton_method(:spans) { test_spans }

    yield(test_adapter) if block_given?

    # Clean up subscription
    ActiveSupport::Notifications.unsubscribe(subscription)

    # Restore original subscribers
    original_subscribers.each do |subscriber|
      ActiveSupport::Notifications.notifier.subscribe(subscriber.pattern, subscriber)
    end
  end

  # Helper to handle API error tests by temporarily disabling telemetry
  def with_disabled_telemetry
    # Store original configuration
    original_configuration = Tasker::Configuration.configuration.dup

    # Create a test configuration with telemetry disabled
    test_configuration = Tasker::Configuration.new
    test_configuration.enable_telemetry = false

    # Override the singleton instance
    Tasker::Configuration.instance_variable_set(:@configuration, test_configuration)

    yield if block_given?

    # Restore the original configuration
    Tasker::Configuration.instance_variable_set(:@configuration, original_configuration)
  end
end
