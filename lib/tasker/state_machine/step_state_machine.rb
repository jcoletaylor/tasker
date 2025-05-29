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
                      Constants::WorkflowStepStatuses::CANCELLED,
                      Constants::WorkflowStepStatuses::RESOLVED_MANUALLY] # Allow manual resolution

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
          "Step #{step.workflow_step_id} transitioning from #{step.status} to #{transition.to_state}"
        end
      end

      after_transition do |step, transition|
        # Determine the appropriate event name based on the transition
        event_name = determine_transition_event_name(transition.from_state, transition.to_state)

        # Only fire the event if we have a valid event name
        if event_name
          # Fire the lifecycle event with step context
          StepStateMachine.safe_fire_event(
            event_name,
            {
              task_id: step.task_id,
              step_id: step.workflow_step_id,
              step_name: step.name,
              from_state: transition.from_state,
              to_state: transition.to_state,
              transitioned_at: Time.zone.now
            }
          )
        end
      end

      # Guard clauses for transition validation
      guard_transition(to: Constants::WorkflowStepStatuses::IN_PROGRESS) do |step|
        # Only allow start if step is pending AND dependencies are met
        current_status = step.state_machine.current_state
        current_status == Constants::WorkflowStepStatuses::PENDING &&
          StepStateMachine.step_dependencies_met?(step)
      end

      guard_transition(to: Constants::WorkflowStepStatuses::COMPLETE) do |step|
        # Only allow completion from in_progress state (proper workflow execution)
        current_status = step.state_machine.current_state
        current_status == Constants::WorkflowStepStatuses::IN_PROGRESS
      end

      guard_transition(to: Constants::WorkflowStepStatuses::ERROR) do |step|
        # Allow error transition from in_progress or pending state
        current_status = step.state_machine.current_state
        [Constants::WorkflowStepStatuses::IN_PROGRESS,
         Constants::WorkflowStepStatuses::PENDING].include?(current_status)
      end

      guard_transition(to: Constants::WorkflowStepStatuses::RESOLVED_MANUALLY) do |step|
        # Allow manual resolution from pending or error states
        current_status = step.state_machine.current_state
        [Constants::WorkflowStepStatuses::PENDING,
         Constants::WorkflowStepStatuses::ERROR].include?(current_status)
      end

      # Class methods for state machine management
      class << self
        # Hashmap for efficient event name lookup based on state transitions
        TRANSITION_EVENT_MAP = {
          # Initial state transitions (from nil/initial)
          [nil, Constants::WorkflowStepStatuses::PENDING] => Constants::StepEvents::INITIALIZE_REQUESTED,
          [nil, Constants::WorkflowStepStatuses::IN_PROGRESS] => Constants::StepEvents::EXECUTION_REQUESTED,
          [nil, Constants::WorkflowStepStatuses::COMPLETE] => Constants::StepEvents::COMPLETED,
          [nil, Constants::WorkflowStepStatuses::ERROR] => Constants::StepEvents::FAILED,
          [nil, Constants::WorkflowStepStatuses::CANCELLED] => Constants::StepEvents::CANCELLED,
          [nil, Constants::WorkflowStepStatuses::RESOLVED_MANUALLY] => Constants::StepEvents::RESOLVED_MANUALLY,

          # Normal state transitions
          [Constants::WorkflowStepStatuses::PENDING,
           Constants::WorkflowStepStatuses::IN_PROGRESS] => Constants::StepEvents::EXECUTION_REQUESTED,
          [Constants::WorkflowStepStatuses::PENDING,
           Constants::WorkflowStepStatuses::ERROR] => Constants::StepEvents::FAILED,
          [Constants::WorkflowStepStatuses::PENDING,
           Constants::WorkflowStepStatuses::CANCELLED] => Constants::StepEvents::CANCELLED,
          [Constants::WorkflowStepStatuses::PENDING,
           Constants::WorkflowStepStatuses::RESOLVED_MANUALLY] => Constants::StepEvents::RESOLVED_MANUALLY,

          [Constants::WorkflowStepStatuses::IN_PROGRESS,
           Constants::WorkflowStepStatuses::COMPLETE] => Constants::StepEvents::COMPLETED,
          [Constants::WorkflowStepStatuses::IN_PROGRESS,
           Constants::WorkflowStepStatuses::ERROR] => Constants::StepEvents::FAILED,
          [Constants::WorkflowStepStatuses::IN_PROGRESS,
           Constants::WorkflowStepStatuses::CANCELLED] => Constants::StepEvents::CANCELLED,

          [Constants::WorkflowStepStatuses::ERROR,
           Constants::WorkflowStepStatuses::PENDING] => Constants::StepEvents::RETRY_REQUESTED,
          [Constants::WorkflowStepStatuses::ERROR,
           Constants::WorkflowStepStatuses::RESOLVED_MANUALLY] => Constants::StepEvents::RESOLVED_MANUALLY
        }.freeze

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
            parent_status = parent.status # This now uses the state machine
            completion_states.include?(parent_status)
          end
        end

        # Safely fire a lifecycle event using dry-events bus
        #
        # @param event_name [String] The event name
        # @param context [Hash] The event context
        # @return [void]
        def safe_fire_event(event_name, context = {})
          if defined?(Tasker::LifecycleEvents)
            # ✅ FIX: Enhance payload with standardized keys expected by TelemetrySubscriber
            enhanced_context = build_standardized_payload(event_name, context)
            Tasker::LifecycleEvents.fire(event_name, enhanced_context)
          else
            Rails.logger.debug { "State machine event: #{event_name} with context: #{context.inspect}" }
          end
        rescue StandardError => e
          Rails.logger.error { "Error firing state machine event #{event_name}: #{e.message}" }
        end

        # Build standardized event payload with all expected keys
        #
        # @param event_name [String] The event name
        # @param context [Hash] The base context
        # @return [Hash] Enhanced context with standardized payload structure
        def build_standardized_payload(event_name, context)
          # Base payload with core identifiers
          enhanced_context = {
            # Core identifiers (always present)
            task_id: context[:task_id],
            step_id: context[:step_id],
            step_name: context[:step_name],

            # State transition information
            from_state: context[:from_state],
            to_state: context[:to_state],

            # Timing information (provide defaults for missing keys)
            started_at: context[:started_at] || context[:transitioned_at],
            completed_at: context[:completed_at] || context[:transitioned_at],
            execution_duration: context[:execution_duration] || 0.0,

            # Error information (for error events)
            error_message: context[:error_message] || context[:error] || 'Unknown error',
            exception_class: context[:exception_class] || 'StandardError',
            attempt_number: context[:attempt_number] || 1,

            # Additional context
            transitioned_at: context[:transitioned_at] || Time.zone.now
          }

          # Merge in any additional context provided
          enhanced_context.merge!(context.except(
            :task_id, :step_id, :step_name, :from_state, :to_state,
            :started_at, :completed_at, :execution_duration,
            :error_message, :exception_class, :attempt_number, :transitioned_at
          ))

          enhanced_context
        end

        # Determine the appropriate event name for a state transition using hashmap lookup
        #
        # @param from_state [String, nil] The source state
        # @param to_state [String] The target state
        # @return [String, nil] The event name or nil if no mapping exists
        def determine_transition_event_name(from_state, to_state)
          transition_key = [from_state, to_state]
          event_name = TRANSITION_EVENT_MAP[transition_key]

          if event_name.nil?
            # For unexpected transitions, log a warning and return nil to skip event firing
            Rails.logger.warn do
              "Unexpected step state transition: #{from_state || 'initial'} → #{to_state}. " \
                'No event will be fired for this transition.'
            end
          end

          event_name
        end
      end

      private

      # Safely fire a lifecycle event
      #
      # @param event_name [String] The event name
      # @param context [Hash] The event context
      # @return [void]
      def safe_fire_event(event_name, context = {})
        self.class.safe_fire_event(event_name, context)
      end

      # Determine the appropriate event name for a state transition
      #
      # @param from_state [String, nil] The source state
      # @param to_state [String] The target state
      # @return [String] The event name
      def determine_transition_event_name(from_state, to_state)
        self.class.determine_transition_event_name(from_state, to_state)
      end
    end
  end
end
