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
          Constants::TaskEvents::BEFORE_TRANSITION,
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
        # Determine the appropriate event name based on the transition
        event_name = determine_transition_event_name(transition.from_state, transition.to_state)

        # Only fire the event if we have a valid event name
        if event_name
          # Fire the lifecycle event with task context
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
        end
      end

      # Guard clauses for transition validation
      guard_transition(to: Constants::TaskStatuses::PENDING) do |task, transition|
        # Don't allow transition to pending if already pending (idempotent)
        current_status = task.state_machine.current_state
        current_status != Constants::TaskStatuses::PENDING
      end

      guard_transition(to: Constants::TaskStatuses::IN_PROGRESS) do |task|
        # Only allow start if task is not already processing
        current_status = task.state_machine.current_state
        current_status == Constants::TaskStatuses::PENDING
      end

      guard_transition(to: Constants::TaskStatuses::COMPLETE) do |task, transition|
        # Don't allow transition to complete if already complete (idempotent)
        current_status = task.state_machine.current_state
        if current_status == Constants::TaskStatuses::COMPLETE
          return false
        end

        # Only allow completion from in_progress state and all steps complete
        current_status == Constants::TaskStatuses::IN_PROGRESS &&
          !TaskStateMachine.task_has_incomplete_steps?(task)
      end

      guard_transition(to: Constants::TaskStatuses::ERROR) do |task, transition|
        # Don't allow transition to error if already in error (idempotent)
        current_status = task.state_machine.current_state
        if current_status == Constants::TaskStatuses::ERROR
          return false
        end

        # Allow error transition from in_progress or pending state
        [Constants::TaskStatuses::IN_PROGRESS, Constants::TaskStatuses::PENDING].include?(current_status)
      end

      # Class methods for state machine management
      class << self
        # Hashmap for efficient event name lookup based on state transitions
        TRANSITION_EVENT_MAP = {
          # Initial state transitions (from nil/initial)
          [nil, Constants::TaskStatuses::PENDING] => Constants::TaskEvents::INITIALIZE_REQUESTED,
          [nil, Constants::TaskStatuses::IN_PROGRESS] => Constants::TaskEvents::START_REQUESTED,
          [nil, Constants::TaskStatuses::COMPLETE] => Constants::TaskEvents::COMPLETED,
          [nil, Constants::TaskStatuses::ERROR] => Constants::TaskEvents::FAILED,
          [nil, Constants::TaskStatuses::CANCELLED] => Constants::TaskEvents::CANCELLED,
          [nil, Constants::TaskStatuses::RESOLVED_MANUALLY] => Constants::TaskEvents::RESOLVED_MANUALLY,

          # Normal state transitions
          [Constants::TaskStatuses::PENDING,
           Constants::TaskStatuses::IN_PROGRESS] => Constants::TaskEvents::START_REQUESTED,
          [Constants::TaskStatuses::PENDING, Constants::TaskStatuses::CANCELLED] => Constants::TaskEvents::CANCELLED,

          [Constants::TaskStatuses::IN_PROGRESS,
           Constants::TaskStatuses::PENDING] => Constants::TaskEvents::INITIALIZE_REQUESTED,
          [Constants::TaskStatuses::IN_PROGRESS, Constants::TaskStatuses::COMPLETE] => Constants::TaskEvents::COMPLETED,
          [Constants::TaskStatuses::IN_PROGRESS, Constants::TaskStatuses::ERROR] => Constants::TaskEvents::FAILED,
          [Constants::TaskStatuses::IN_PROGRESS,
           Constants::TaskStatuses::CANCELLED] => Constants::TaskEvents::CANCELLED,

          [Constants::TaskStatuses::ERROR, Constants::TaskStatuses::PENDING] => Constants::TaskEvents::RETRY_REQUESTED,
          [Constants::TaskStatuses::ERROR,
           Constants::TaskStatuses::RESOLVED_MANUALLY] => Constants::TaskEvents::RESOLVED_MANUALLY
        }.freeze

        # Safely fire a lifecycle event using dry-events bus
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
        rescue ActiveRecord::InvalidForeignKey => e
          # Handle foreign key violations specifically (common in test environments)
          Rails.logger.warn { "Foreign key violation firing event #{event_name}: #{e.message}" }
        rescue StandardError => e
          Rails.logger.error { "Error firing state machine event #{event_name}: #{e.message}" }
          Rails.logger.error { e.backtrace.join("\n") } if Rails.env.development?
        end

        # Determine the transition event name based on states using hashmap lookup
        #
        # @param from_state [String] The from state
        # @param to_state [String] The to state
        # @return [String, nil] The event name or nil if no mapping exists
        def determine_transition_event_name(from_state, to_state)
          transition_key = [from_state, to_state]
          event_name = TRANSITION_EVENT_MAP[transition_key]

          if event_name.nil?
            # For unexpected transitions, log a warning and return nil to skip event firing
            Rails.logger.warn do
              "Unexpected task state transition: #{from_state || 'initial'} → #{to_state}. " \
                'No event will be fired for this transition.'
            end
          end

          event_name
        end

        # Check if a task has incomplete steps
        #
        # @param task [Task] The task to check
        # @return [Boolean] True if there are incomplete steps
        def task_has_incomplete_steps?(task)
          return false unless task.respond_to?(:workflow_steps)

          incomplete_statuses = [
            Constants::WorkflowStepStatuses::PENDING,
            Constants::WorkflowStepStatuses::IN_PROGRESS,
            Constants::WorkflowStepStatuses::ERROR
          ]

          task.workflow_steps.any? do |step|
            step_status = step.status # This now uses the state machine
            incomplete_statuses.include?(step_status)
          end
        end
      end
    end
  end
end
