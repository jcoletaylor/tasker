# frozen_string_literal: true

require_relative 'state_machine/task_state_machine'
require_relative 'state_machine/step_state_machine'

module Tasker
  # StateMachine module provides declarative state management for tasks and steps
  #
  # This module integrates Statesman-based state machines with the existing
  # Tasker lifecycle events system to provide a unified, event-driven approach
  # to workflow state management.
  module StateMachine
    # Exception raised when an invalid state transition is attempted
    class InvalidStateTransition < StandardError; end

    # Compatibility module for legacy state management
    module Compatibility
      # Legacy method for updating status with state machine integration
      #
      # @param entity [Object] The entity (task or step) to update
      # @param new_status [String] The new status to transition to
      # @param metadata [Hash] Optional metadata for the transition
      # @return [Boolean] True if transition succeeded
      def update_status!(entity, new_status, metadata = {})
        return false unless entity.respond_to?(:state_machine)

        entity.state_machine.transition_to!(new_status, metadata)
        true
      rescue Statesman::GuardFailedError, Statesman::TransitionFailedError => e
        Rails.logger.warn { "State transition failed: #{e.message}" }
        false
      end
    end

    # Configure state machine behavior
    class << self
      # Configure Statesman for Tasker
      #
      # @return [void]
      def configure_statesman
        # Statesman doesn't require global configuration
        # State machines use ActiveRecord adapters through transition models
        true
      end

      # Initialize state machines for a task
      #
      # @param task [Task] The task to initialize
      # @return [TaskStateMachine] The initialized state machine
      def initialize_task_state_machine(task)
        TaskStateMachine.new(task)
      end

      # Initialize state machines for a step
      #
      # @param step [WorkflowStep] The step to initialize
      # @return [StepStateMachine] The initialized state machine
      def initialize_step_state_machine(step)
        StepStateMachine.new(step)
      end

      # Check if state machines are properly configured
      #
      # @return [Boolean] True if configuration is valid
      def configured?
        !!(defined?(Statesman) &&
           TaskStateMachine.respond_to?(:new) &&
           StepStateMachine.respond_to?(:new))
      end

      # Get statistics about state machine usage
      #
      # @return [Hash] Statistics hash
      def statistics
        {
          task_states: Constants::VALID_TASK_STATUSES,
          step_states: Constants::VALID_WORKFLOW_STEP_STATUSES,
          configured: configured?
        }
      end
    end
  end
end
