# frozen_string_literal: true

# Helper module for isolated telemetry testing
module TelemetryTestHelper
  # Setup isolated telemetry for a test
  # This temporarily replaces the global telemetry adapters with test-specific ones
  # and ensures cleanup after the test
  def with_isolated_telemetry(adapter = nil)
    adapter ||= MemoryAdapter.new

    # Store original configuration
    original_configuration = Tasker::Configuration.configuration.dup

    # Clear any existing observers
    original_observers = Tasker::LifecycleEvents.observers.dup
    Tasker::LifecycleEvents.reset_observers

    # Create a test configuration
    test_configuration = Tasker::Configuration.new
    test_observability = Tasker::Configuration::ObservabilityConfiguration.new
    test_observability.enable_telemetry = true
    test_configuration.observability = test_observability

    # Override the singleton instance
    Tasker::Configuration.instance_variable_set(:@configuration, test_configuration)

    # Register test adapter
    observer = Tasker::Observability::LifecycleObserver.new([adapter])
    Tasker::LifecycleEvents.register_observer(observer)

    yield(adapter) if block_given?

    # Restore the original configuration
    Tasker::Configuration.instance_variable_set(:@configuration, original_configuration)

    # Restore original observers
    Tasker::LifecycleEvents.reset_observers
    original_observers.each do |obs|
      Tasker::LifecycleEvents.register_observer(obs)
    end
  end

  # Helper to handle API error tests by temporarily disabling telemetry
  def with_disabled_telemetry
    # Store original configuration
    original_configuration = Tasker::Configuration.configuration.dup

    # Create a test configuration with telemetry disabled
    test_configuration = Tasker::Configuration.new
    test_observability = Tasker::Configuration::ObservabilityConfiguration.new
    test_observability.enable_telemetry = false
    test_configuration.observability = test_observability

    # Override the singleton instance
    Tasker::Configuration.instance_variable_set(:@configuration, test_configuration)

    yield if block_given?

    # Restore the original configuration
    Tasker::Configuration.instance_variable_set(:@configuration, original_configuration)
  end
end
