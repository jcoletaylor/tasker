# frozen_string_literal: true

# Test helpers for event-driven workflow orchestration
#
# These helpers provide utilities for tests that want to use the orchestration system.
# Orchestration is the primary workflow system, so these helpers focus on proper
# state management rather than dynamic workarounds.
module OrchestrationHelpers
  # Initialize the orchestration system for tests that need it
  #
  # This ensures clean orchestration state for tests. Since orchestration
  # is now the primary workflow system, this mainly resets state rather
  # than conditionally initializing.
  #
  # @example
  #   before do
  #     initialize_orchestration_for_test
  #   end
  def initialize_orchestration_for_test
    # Ensure clean state
    Tasker::Orchestration::Coordinator.instance_variable_set(:@initialized, false)

    # Initialize the orchestration system (should already be done by Rails, but defensive)
    Tasker::Orchestration::Coordinator.initialize!
  end

  # Clean up orchestration system after tests
  #
  # Call this in an after block to clean up orchestration state
  #
  # @example
  #   after do
  #     cleanup_orchestration_after_test
  #   end
  def cleanup_orchestration_after_test
    # Reset initialization state
    Tasker::Orchestration::Coordinator.instance_variable_set(:@initialized, false)
  end

  # Clean up database state that might interfere with orchestration tests
  #
  # This removes completed tasks from other tests (like before(:all) blocks)
  # that could cause state pollution in orchestration testing
  #
  # @param task_name [String] The name of the task to clean up
  def cleanup_task_state_for_orchestration(task_name)
    # Remove any existing tasks with this name that might be in completed state
    # from other tests (especially before(:all) blocks)
    # The database cascade will handle cleaning up associated workflow steps
    Tasker::Task.joins(:named_task)
                .where(named_task: { name: task_name })
                .destroy_all
  end

  # Register the DummyTask handler with proper setup
  #
  # This is the preferred method for orchestration tests - uses the real
  # DummyTask infrastructure rather than dynamic workarounds
  def register_dummy_task_handler
    register_task_handler(DummyTask::TASK_REGISTRY_NAME, DummyTask)
  end
end

# Include in RSpec configuration
RSpec.configure do |config|
  config.include OrchestrationHelpers
end
