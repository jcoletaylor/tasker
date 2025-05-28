# frozen_string_literal: true

require 'statesman'
require_relative '../constants'

module Tasker
  module StateMachine
    # StepStateMachine defines state transitions for workflow steps using Statesman
    #
    # This state machine manages workflow step lifecycle states and integrates with
    # the existing event system to provide declarative state management.
    class StepStateMachine
      include Statesman::Machine

      # Define all step states using existing constants
      state Constants::WorkflowStepStatuses::PENDING, initial: true
      state Constants::WorkflowStepStatuses::IN_PROGRESS
      state Constants::WorkflowStepStatuses::COMPLETE
      state Constants::WorkflowStepStatuses::ERROR
      state Constants::WorkflowStepStatuses::CANCELLED
      state Constants::WorkflowStepStatuses::RESOLVED_MANUALLY

      # Define state transitions based on existing StateTransition definitions
      transition from: Constants::WorkflowStepStatuses::PENDING,
                 to: [Constants::WorkflowStepStatuses::IN_PROGRESS,
                      Constants::WorkflowStepStatuses::ERROR,
                      Constants::WorkflowStepStatuses::CANCELLED]

      transition from: Constants::WorkflowStepStatuses::IN_PROGRESS,
                 to: [Constants::WorkflowStepStatuses::COMPLETE,
                      Constants::WorkflowStepStatuses::ERROR,
                      Constants::WorkflowStepStatuses::CANCELLED]

      transition from: Constants::WorkflowStepStatuses::ERROR,
                 to: [Constants::WorkflowStepStatuses::PENDING,
                      Constants::WorkflowStepStatuses::RESOLVED_MANUALLY]

      # Callbacks for state transitions
      before_transition do |step, transition|
        # Log the transition for debugging
        Rails.logger.debug do
          "Step #{step.workflow_step_id} transitioning from #{step.read_attribute(:status)} to #{transition.to_state}"
        end
      end

      after_transition do |step, transition|
        # Update the step's status in the database
        if step.respond_to?(:update_column) && step.persisted?
          begin
            step.update_column(:status, transition.to_state)
          rescue ActiveRecord::InvalidForeignKey => e
            # Handle foreign key violations gracefully (common in test environments)
            Rails.logger.warn { "Foreign key violation during step transition: #{e.message}" }
          end
        end

        # Log the completed transition
        Rails.logger.debug { "Step #{step.workflow_step_id} transitioned to #{transition.to_state}" }
      end

      # Guard clauses for transition validation
      guard_transition(to: Constants::WorkflowStepStatuses::IN_PROGRESS) do |step|
        # Only allow execution if step is pending and dependencies are met
        current_status = step.read_attribute(:status) || step[:status]
        current_status == Constants::WorkflowStepStatuses::PENDING &&
          Tasker::StateMachine::StepStateMachine.step_dependencies_met?(step)
      end

      guard_transition(to: Constants::WorkflowStepStatuses::COMPLETE) do |step|
        # Only allow completion from in_progress state
        current_status = step.read_attribute(:status) || step[:status]
        current_status == Constants::WorkflowStepStatuses::IN_PROGRESS
      end

      guard_transition(to: Constants::WorkflowStepStatuses::ERROR) do |step|
        # Allow error transition from pending or in_progress state
        current_status = step.read_attribute(:status) || step[:status]
        [Constants::WorkflowStepStatuses::PENDING,
         Constants::WorkflowStepStatuses::IN_PROGRESS].include?(current_status)
      end

      guard_transition(to: Constants::WorkflowStepStatuses::PENDING) do |step|
        # Allow retry from error state, or initial pending state
        current_status = step.read_attribute(:status) || step[:status]
        current_status == Constants::WorkflowStepStatuses::ERROR ||
          current_status.nil?
      end

      # Class methods for state machine management
      class << self
        # Check if step dependencies are met
        #
        # @param step [WorkflowStep] The step to check
        # @return [Boolean] True if all dependencies are satisfied
        def step_dependencies_met?(step)
          return true unless step.respond_to?(:parents)

          # Check if all parent steps are complete
          step.parents.all? do |parent|
            completion_states = [
              Constants::WorkflowStepStatuses::COMPLETE,
              Constants::WorkflowStepStatuses::RESOLVED_MANUALLY
            ]
            parent_status = parent.read_attribute(:status) || parent[:status]
            completion_states.include?(parent_status)
          end
        end
      end

      private

      # Safely fire a lifecycle event
      #
      # @param event_name [String] The event name
      # @param context [Hash] The event context
      # @return [void]
      def safe_fire_event(event_name, context = {})
        if defined?(Tasker::LifecycleEvents)
          Tasker::LifecycleEvents.fire(event_name, context)
        else
          Rails.logger.debug { "State machine event: #{event_name} with context: #{context.inspect}" }
        end
      rescue StandardError => e
        Rails.logger.error { "Error firing state machine event #{event_name}: #{e.message}" }
      end
    end
  end
end
