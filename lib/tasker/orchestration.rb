# frozen_string_literal: true

# Tasker::Orchestration namespace for event-driven workflow orchestration
#
# This module provides a declarative, event-driven alternative to the imperative
# TaskHandler workflow loop. It coordinates workflow execution through state machine
# events and publisher/subscriber patterns.
#
# Components:
# - Events::Publisher: Unified event publisher for all workflow events (singleton)
# - ViableStepDiscovery: Discovers which steps can be executed based on workflow state
# - StepExecutor: Handles the execution of workflow steps via state machine transitions
# - TaskFinalizer: Handles task completion and finalization logic
# - Coordinator: Manages the setup and initialization of the event-driven workflow system
#
# Usage:
#   # Initialize the workflow orchestration system (do this once at startup)
#   Tasker::Orchestration::Coordinator.initialize!
#
#   # Access the unified event publisher
#   publisher = Tasker::Events::Publisher.instance
#
# Benefits:
# - Declarative: Steps declare what events they respond to
# - Testable: Each component can be tested in isolation
# - Extensible: Easy to add new behaviors via event subscribers
# - Observable: Rich event stream for debugging and monitoring
# - Concurrent-Safe: State machines handle race conditions
# - Audit Trail: Complete history of all state transitions

# Explicitly require orchestration components for predictable loading
require_relative 'orchestration/viable_step_discovery'
require_relative 'orchestration/step_executor'
require_relative 'orchestration/task_finalizer'
require_relative 'orchestration/task_initializer'
require_relative 'orchestration/task_reenqueuer'
require_relative 'orchestration/step_sequence_factory'
require_relative 'orchestration/coordinator'

module Tasker
  module Orchestration
    # All orchestration components are now explicitly loaded above
    # This provides predictable loading order and avoids autoload complexity
  end
end
