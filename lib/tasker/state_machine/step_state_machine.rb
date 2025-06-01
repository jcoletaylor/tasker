# frozen_string_literal: true

require 'statesman'
require_relative '../constants'
require 'tasker/events/event_payload_builder'
require_relative '../concerns/event_publisher'

module Tasker
  module StateMachine
    # StepStateMachine defines state transitions for workflow steps using Statesman
    #
    # This state machine manages workflow step lifecycle states and integrates with
    # the existing event system to provide declarative state management.
    class StepStateMachine
      include Statesman::Machine
      extend Tasker::Concerns::EventPublisher

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
        # Handle idempotent transitions using existing helper method
        if StepStateMachine.idempotent_transition?(step, transition.to_state)
          # Abort the transition by raising GuardFailedError
          raise Statesman::GuardFailedError, "Already in target state #{transition.to_state}"
        end

        # Log the transition for debugging
        effective_current_state = StepStateMachine.effective_current_state(step)
        Rails.logger.debug do
          "Step #{step.workflow_step_id} transitioning from #{effective_current_state} to #{transition.to_state}"
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

      # Guard clauses for business logic only
      # Let Statesman handle state transition validation and idempotent calls

      guard_transition(to: Constants::WorkflowStepStatuses::IN_PROGRESS) do |step, transition|
        # Only business rule: check dependencies are met
        StepStateMachine.step_dependencies_met?(step)
      end

      # No other guard clauses needed!
      # - State transition validation is handled by the transition definitions above
      # - Idempotent transitions are handled by Statesman automatically
      # - Simple state changes (PENDING->ERROR, IN_PROGRESS->COMPLETE, etc.) don't need guards

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

        # Class-level wrapper methods for guard clause context
        # These delegate to instance methods to provide clean access from guard clauses

        # Check if a transition is idempotent (current state == target state)
        #
        # @param step [WorkflowStep] The step to check
        # @param target_state [String] The target state
        # @return [Boolean] True if this is an idempotent transition
        def idempotent_transition?(step, target_state)
          current_state = step.state_machine.current_state
          effective_current_state = current_state.blank? ? Constants::WorkflowStepStatuses::PENDING : current_state
          is_idempotent = effective_current_state == target_state

          if is_idempotent
            Rails.logger.debug do
              "StepStateMachine: Allowing idempotent transition to #{target_state} for step #{step.workflow_step_id}"
            end
          end

          is_idempotent
        end

        # Get the effective current state, handling blank/empty states
        #
        # @param step [WorkflowStep] The step to check
        # @return [String] The effective current state (blank states become PENDING)
        def effective_current_state(step)
          current_state = step.state_machine.current_state
          current_state.blank? ? Constants::WorkflowStepStatuses::PENDING : current_state
        end

        # Log an invalid from-state transition
        #
        # @param step [WorkflowStep] The step
        # @param current_state [String] The current state
        # @param target_state [String] The target state
        # @param reason [String] The reason for the restriction
        def log_invalid_from_state(step, current_state, target_state, reason)
          Rails.logger.debug do
            "StepStateMachine: Cannot transition to #{target_state} from '#{current_state}' " \
            "(step #{step.workflow_step_id}). #{reason}."
          end
        end

        # Log when dependencies are not met
        #
        # @param step [WorkflowStep] The step
        # @param target_state [String] The target state
        def log_dependencies_not_met(step, target_state)
          Rails.logger.debug do
            "StepStateMachine: Cannot transition step #{step.workflow_step_id} to #{target_state} - " \
            "dependencies not satisfied. Check parent step completion status."
          end
        end

        # Log the result of a transition check
        #
        # @param step [WorkflowStep] The step
        # @param target_state [String] The target state
        # @param result [Boolean] Whether the transition is allowed
        # @param reason [String] The reason for the result
        def log_transition_result(step, target_state, result, reason)
          if result
            Rails.logger.debug do
              "StepStateMachine: Allowing transition to #{target_state} for step #{step.workflow_step_id} (#{reason})"
            end
          else
            Rails.logger.debug do
              "StepStateMachine: Blocking transition to #{target_state} for step #{step.workflow_step_id} (#{reason} failed)"
            end
          end
        end

        # Check if step dependencies are met
        #
        # @param step [WorkflowStep] The step to check
        # @return [Boolean] True if all dependencies are satisfied
        def step_dependencies_met?(step)
          # Handle cases where step doesn't have parents association or it's not loaded
          begin
            # If step doesn't respond to parents, assume no dependencies
            return true unless step.respond_to?(:parents)

            # If parents association exists but is empty, no dependencies to check
            parents = step.parents
            return true if parents.nil? || parents.empty?

            # Check if all parent steps are complete
            parents.all? do |parent|
              completion_states = [
                Constants::WorkflowStepStatuses::COMPLETE,
                Constants::WorkflowStepStatuses::RESOLVED_MANUALLY
              ]
              # Use state_machine.current_state to avoid circular reference with parent.status
              current_state = parent.state_machine.current_state
              parent_status = current_state.blank? ? Constants::WorkflowStepStatuses::PENDING : current_state
              is_complete = completion_states.include?(parent_status)

              unless is_complete
                Rails.logger.debug do
                  "StepStateMachine: Step #{step.workflow_step_id} dependency not met - " \
                  "parent step #{parent.workflow_step_id} is '#{parent_status}', needs to be complete"
                end
              end

              is_complete
            end
          rescue StandardError => e
            # If there's an error checking dependencies, log it and assume dependencies are met
            # This prevents dependency checking from blocking execution in edge cases
            Rails.logger.warn do
              "StepStateMachine: Error checking dependencies for step #{step.workflow_step_id}: #{e.message}. " \
              "Assuming dependencies are met."
            end
            true
          end
        end

        # Safely fire a lifecycle event using dry-events bus
        #
        # @param event_name [String] The event name
        # @param context [Hash] The event context
        # @return [void]
        def safe_fire_event(event_name, context = {})
          # Use EventPayloadBuilder for consistent payload structure
          step = extract_step_from_context(context)
          task = step&.task

          if step && task
            # Determine event type from event name
            event_type = determine_event_type_from_name(event_name)

            # Use EventPayloadBuilder for standardized payload
            enhanced_context = Tasker::Events::EventPayloadBuilder.build_step_payload(
              step,
              task,
              event_type: event_type,
              additional_context: context
            )
          else
            # Fallback to enhanced context if step/task not available
            enhanced_context = build_standardized_payload(event_name, context)
          end

          publish_event(event_name, enhanced_context)
        end

        # Extract step object from context for EventPayloadBuilder
        #
        # @param context [Hash] The event context
        # @return [WorkflowStep, nil] The step object if available
        def extract_step_from_context(context)
          step_id = context[:step_id]
          return nil unless step_id

          # Try to find the step - handle both string and numeric IDs
          Tasker::WorkflowStep.find_by(workflow_step_id: step_id) ||
            Tasker::WorkflowStep.find_by(id: step_id)
        rescue StandardError => e
          Rails.logger.warn { "Could not find step with ID #{step_id}: #{e.message}" }
          nil
        end

        # Determine event type from event name for EventPayloadBuilder
        #
        # @param event_name [String] The event name
        # @return [Symbol] The event type
        def determine_event_type_from_name(event_name)
          case event_name
          when /completed/i
            :completed
          when /failed/i, /error/i
            :failed
          when /execution_requested/i, /started/i
            :started
          when /retry/i
            :retry
          when /backoff/i
            :backoff
          else
            :unknown
          end
        end

        # Build standardized event payload with all expected keys (legacy fallback)
        #
        # @param event_name [String] The event name
        # @param context [Hash] The base context
        # @return [Hash] Enhanced context with standardized payload structure
        def build_standardized_payload(_event_name, context)
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
