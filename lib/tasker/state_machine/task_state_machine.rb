# frozen_string_literal: true

require 'statesman'
require_relative '../constants'

module Tasker
  module StateMachine
    # TaskStateMachine defines state transitions for tasks using Statesman
    #
    # This state machine manages task lifecycle states and integrates with
    # the existing event system to provide declarative state management.
    class TaskStateMachine
      include Statesman::Machine

      # Define all task states using existing constants
      state Constants::TaskStatuses::PENDING, initial: true
      state Constants::TaskStatuses::IN_PROGRESS
      state Constants::TaskStatuses::COMPLETE
      state Constants::TaskStatuses::ERROR
      state Constants::TaskStatuses::CANCELLED
      state Constants::TaskStatuses::RESOLVED_MANUALLY

      # Define state transitions based on existing StateTransition definitions
      transition from: Constants::TaskStatuses::PENDING,
                 to: Constants::TaskStatuses::IN_PROGRESS

      transition from: Constants::TaskStatuses::IN_PROGRESS,
                 to: [Constants::TaskStatuses::COMPLETE,
                      Constants::TaskStatuses::ERROR,
                      Constants::TaskStatuses::CANCELLED,
                      Constants::TaskStatuses::PENDING]

      transition from: Constants::TaskStatuses::ERROR,
                 to: [Constants::TaskStatuses::PENDING,
                      Constants::TaskStatuses::RESOLVED_MANUALLY]

      transition from: Constants::TaskStatuses::PENDING,
                 to: Constants::TaskStatuses::CANCELLED

      # Callbacks for lifecycle event integration
      before_transition do |task, transition|
        # Fire before transition event
        TaskStateMachine.safe_fire_event(
          'task.before_transition',
          {
            task_id: task.task_id,
            from_state: transition.from_state,
            to_state: transition.to_state,
            transition_event: TaskStateMachine.determine_transition_event_name(transition.from_state,
                                                                               transition.to_state)
          }
        )
      end

      after_transition do |task, transition|
        # Fire after transition event based on target state
        event_name = case transition.to_state
                     when Constants::TaskStatuses::PENDING
                       if transition.from_state == Constants::TaskStatuses::ERROR
                         'task.retry_requested'
                       elsif transition.from_state == Constants::TaskStatuses::IN_PROGRESS
                         'task.reenqueue_requested'
                       else
                         'task.initialize_requested'
                       end
                     when Constants::TaskStatuses::IN_PROGRESS
                       'task.start_requested'
                     when Constants::TaskStatuses::COMPLETE
                       'task.completed'
                     when Constants::TaskStatuses::ERROR
                       'task.failed'
                     when Constants::TaskStatuses::CANCELLED
                       'task.cancelled'
                     when Constants::TaskStatuses::RESOLVED_MANUALLY
                       'task.resolved_manually'
                     else
                       'task.state_changed'
                     end

        # Fire the lifecycle event
        TaskStateMachine.safe_fire_event(
          event_name,
          {
            task_id: task.task_id,
            task_name: task.name,
            task_context: task.context,
            from_state: transition.from_state,
            to_state: transition.to_state,
            transitioned_at: Time.zone.now
          }
        )

        # Update the task's status in the database
        if task.respond_to?(:update_column) && task.persisted?
          begin
            task.update_column(:status, transition.to_state)
          rescue ActiveRecord::InvalidForeignKey => e
            # Handle foreign key violations gracefully (common in test environments)
            Rails.logger.warn { "Foreign key violation during task transition: #{e.message}" }
          end
        end
      end

      # Guard clauses for transition validation
      guard_transition(to: Constants::TaskStatuses::IN_PROGRESS) do |task|
        # Only allow start if task is not already processing
        current_status = task.read_attribute(:status) || task[:status]
        current_status == Constants::TaskStatuses::PENDING
      end

      guard_transition(to: Constants::TaskStatuses::COMPLETE) do |task|
        # Only allow completion from in_progress state
        current_status = task.read_attribute(:status) || task[:status]
        current_status == Constants::TaskStatuses::IN_PROGRESS &&
          !TaskStateMachine.task_has_incomplete_steps?(task)
      end

      guard_transition(to: Constants::TaskStatuses::ERROR) do |task|
        # Allow error transition from in_progress state
        current_status = task.read_attribute(:status) || task[:status]
        current_status == Constants::TaskStatuses::IN_PROGRESS
      end

      # Safely fire a lifecycle event using dry-events bus
      #
      # @param event_name [String] The event name
      # @param context [Hash] The event context
      # @return [void]
      def self.safe_fire_event(event_name, context = {})
        if defined?(Tasker::LifecycleEvents)
          Tasker::LifecycleEvents.fire(event_name, context)
        else
          Rails.logger.debug { "State machine event: #{event_name} with context: #{context.inspect}" }
        end
      rescue ActiveRecord::InvalidForeignKey => e
        # Handle foreign key violations specifically (common in test environments)
        Rails.logger.warn { "Foreign key violation firing event #{event_name}: #{e.message}" }
      rescue StandardError => e
        Rails.logger.error { "Error firing state machine event #{event_name}: #{e.message}" }
        Rails.logger.error { e.backtrace.join("\n") } if Rails.env.development?
      end

      # Determine the transition event name based on states
      #
      # @param from_state [String] The from state
      # @param to_state [String] The to state
      # @return [String] The event name
      def self.determine_transition_event_name(from_state, to_state)
        case [from_state, to_state]
        when [nil, Constants::TaskStatuses::PENDING],
             [Constants::TaskStatuses::IN_PROGRESS, Constants::TaskStatuses::PENDING]
          'initialize_requested'
        when [Constants::TaskStatuses::PENDING, Constants::TaskStatuses::IN_PROGRESS]
          'start_requested'
        when [Constants::TaskStatuses::IN_PROGRESS, Constants::TaskStatuses::COMPLETE]
          'completed'
        when [Constants::TaskStatuses::IN_PROGRESS, Constants::TaskStatuses::ERROR]
          'failed'
        when [Constants::TaskStatuses::ERROR, Constants::TaskStatuses::PENDING]
          'retry_requested'
        when [Constants::TaskStatuses::ERROR, Constants::TaskStatuses::RESOLVED_MANUALLY]
          'resolved_manually'
        when [Constants::TaskStatuses::PENDING, Constants::TaskStatuses::CANCELLED],
             [Constants::TaskStatuses::IN_PROGRESS, Constants::TaskStatuses::CANCELLED]
          'cancelled'
        else
          'state_changed'
        end
      end

      # Check if a task has incomplete steps
      #
      # @param task [Task] The task to check
      # @return [Boolean] True if there are incomplete steps
      def self.task_has_incomplete_steps?(task)
        return false unless task.respond_to?(:workflow_steps)

        incomplete_statuses = [
          Constants::WorkflowStepStatuses::PENDING,
          Constants::WorkflowStepStatuses::IN_PROGRESS,
          Constants::WorkflowStepStatuses::ERROR
        ]

        task.workflow_steps.any? do |step|
          step_status = step.read_attribute(:status) || step[:status]
          incomplete_statuses.include?(step_status)
        end
      end
    end
  end
end
