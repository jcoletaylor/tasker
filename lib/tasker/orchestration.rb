# frozen_string_literal: true

# Tasker::Orchestration namespace for event-driven workflow orchestration
#
# This module provides a declarative, event-driven alternative to the imperative
# TaskHandler workflow loop. It coordinates workflow execution through state machine
# events and publisher/subscriber patterns.
#
# Components:
# - Orchestrator: Coordinates workflow execution through event-driven orchestration
# - ViableStepDiscovery: Discovers which steps can be executed based on workflow state
# - StepExecutor: Handles the execution of workflow steps via state machine transitions
# - TaskFinalizer: Handles task completion and finalization logic
# - Coordinator: Manages the setup and initialization of the event-driven workflow system
#
# Usage:
#   # Initialize the workflow orchestration system (do this once at startup)
#   Tasker::Orchestration::Coordinator.initialize!
#
#   # Process a task using the event-driven system
#   success = Tasker::Orchestration::Coordinator.process_task(task_id)
#
# Benefits:
# - Declarative: Steps declare what events they respond to
# - Testable: Each component can be tested in isolation
# - Extensible: Easy to add new behaviors via event subscribers
# - Observable: Rich event stream for debugging and monitoring
# - Concurrent-Safe: State machines handle race conditions
# - Audit Trail: Complete history of all state transitions

module Tasker
  module Orchestration
    # Autoload orchestration components
    autoload :Orchestrator, 'tasker/orchestration/orchestrator'
    autoload :ViableStepDiscovery, 'tasker/orchestration/viable_step_discovery'
    autoload :StepExecutor, 'tasker/orchestration/step_executor'
    autoload :TaskFinalizer, 'tasker/orchestration/task_finalizer'
    autoload :Coordinator, 'tasker/orchestration/coordinator'
  end
end
