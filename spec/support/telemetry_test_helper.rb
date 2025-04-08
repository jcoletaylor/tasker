# frozen_string_literal: true

# Helper module for isolated telemetry testing
module TelemetryTestHelper
  # Setup isolated telemetry for a test
  # This temporarily replaces the global telemetry adapters with test-specific ones
  # and ensures cleanup after the test
  def with_isolated_telemetry(adapter = nil)
    adapter ||= MemoryAdapter.new
    original_adapters = Tasker::Telemetry.instance_variable_get(:@adapters)

    # Set our test adapter without touching global configuration
    Tasker::Telemetry.instance_variable_set(:@adapters, [adapter])

    # Clear any existing observers
    original_observers = Tasker::LifecycleEvents.observers.dup
    Tasker::LifecycleEvents.reset_observers

    # Reset the telemetry observer
    original_telemetry_observer = Tasker::Telemetry::Observer.instance
    Tasker::Telemetry::Observer.reset_instance

    # Create new observer specifically for this test
    test_observer = Tasker::Telemetry::Observer.new

    yield(adapter) if block_given?

    # Restore the original state
    Tasker::Telemetry.instance_variable_set(:@adapters, original_adapters)
    Tasker::LifecycleEvents.reset_observers
    original_observers.each do |observer|
      Tasker::LifecycleEvents.register_observer(observer)
    end

    # Reset the singleton observer to its original state
    Tasker::Telemetry::Observer.reset_instance
    if original_telemetry_observer
      # Re-register the original instance
      Tasker::Telemetry::Observer.instance_variable_set(:@instance, original_telemetry_observer)
    end
  end

  # Helper to handle API error tests by temporarily disabling telemetry
  def with_disabled_telemetry
    original_adapters = Tasker::Telemetry.instance_variable_get(:@adapters)
    Tasker::Telemetry.instance_variable_set(:@adapters, [])

    yield if block_given?

    Tasker::Telemetry.instance_variable_set(:@adapters, original_adapters)
  end
end
