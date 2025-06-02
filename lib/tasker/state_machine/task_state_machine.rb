# frozen_string_literal: true

require 'statesman'
require_relative '../constants'
require 'tasker/events/event_payload_builder'
require_relative '../concerns/event_publisher'

module Tasker
  module StateMachine
    # TaskStateMachine defines state transitions for tasks using Statesman
    #
    # This state machine manages task lifecycle states and integrates with
    # the existing event system to provide declarative state management.
    class TaskStateMachine
      include Statesman::Machine
      extend Tasker::Concerns::EventPublisher

      # Define all task states using existing constants
      state Constants::TaskStatuses::PENDING, initial: true
      state Constants::TaskStatuses::IN_PROGRESS
      state Constants::TaskStatuses::COMPLETE
      state Constants::TaskStatuses::ERROR
      state Constants::TaskStatuses::CANCELLED
      state Constants::TaskStatuses::RESOLVED_MANUALLY

      # Define state transitions based on existing StateTransition definitions
      # Fixed: Added missing transitions that guard clauses were handling
      transition from: Constants::TaskStatuses::PENDING,
                 to: [Constants::TaskStatuses::IN_PROGRESS,
                      Constants::TaskStatuses::CANCELLED,
                      Constants::TaskStatuses::ERROR] # Allow direct error from pending

      transition from: Constants::TaskStatuses::IN_PROGRESS,
                 to: [Constants::TaskStatuses::COMPLETE,
                      Constants::TaskStatuses::ERROR,
                      Constants::TaskStatuses::CANCELLED,
                      Constants::TaskStatuses::PENDING] # Allow reset to pending

      transition from: Constants::TaskStatuses::ERROR,
                 to: [Constants::TaskStatuses::PENDING,
                      Constants::TaskStatuses::RESOLVED_MANUALLY]

      # Allow cancellation from complete/error states (admin override scenarios)
      transition from: Constants::TaskStatuses::COMPLETE,
                 to: Constants::TaskStatuses::CANCELLED

      transition from: Constants::TaskStatuses::RESOLVED_MANUALLY,
                 to: Constants::TaskStatuses::CANCELLED

      # Callbacks for lifecycle event integration
      before_transition do |task, transition|
        # Handle idempotent transitions using existing helper method
        if TaskStateMachine.idempotent_transition?(task, transition.to_state)
          # Abort the transition by raising GuardFailedError
          raise Statesman::GuardFailedError, "Already in target state #{transition.to_state}"
        end

        # Log the transition for debugging
        effective_current_state = TaskStateMachine.effective_current_state(task)
        Rails.logger.debug do
          "Task #{task.task_id} transitioning from #{effective_current_state} to #{transition.to_state}"
        end

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

      # Guard clauses for business logic only
      # Let Statesman handle state transition validation and idempotent calls

      guard_transition(to: Constants::TaskStatuses::COMPLETE) do |task, _transition|
        # Only business rule: task can only complete when all steps are done
        !TaskStateMachine.task_has_incomplete_steps?(task)
      end

      # No other guard clauses needed!
      # - State transition validation is handled by the transition definitions above
      # - Idempotent transitions are handled by Statesman automatically
      # - Simple state changes don't need business logic validation

      # Class methods for state machine management
      class << self
        # Lazy-loaded hashmap for efficient event name lookup based on state transitions
        # This is built on first access to avoid referencing constants before they're created
        def transition_event_map
          @transition_event_map ||= build_transition_event_map
        end

        # Build the transition event map when needed
        def build_transition_event_map
          # Load mappings from YAML (single source of truth)
          yaml_file = File.join(Tasker::Engine.root, 'config', 'tasker', 'system_events.yml')

          if File.exist?(yaml_file)
            yaml_data = YAML.load_file(yaml_file)
            mappings = yaml_data.dig('state_machine_mappings', 'task_transitions') || []

            # Convert YAML mappings to hash format
            transition_map = {}
            mappings.each do |mapping|
              from_state = mapping['from_state'] # nil for initial transitions
              to_state = mapping['to_state']
              event_constant = mapping['event_constant']

              # Convert to our internal format
              transition_map[[from_state, to_state]] = event_constant
            end

            transition_map.freeze
          else
            # Fallback to hardcoded mappings if YAML not available
            Rails.logger.warn('Tasker: system_events.yml not found, using fallback mappings')
            build_fallback_transition_map
          end
        end

        # Fallback mappings in case YAML is not available
        def build_fallback_transition_map
          {
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
            [Constants::TaskStatuses::PENDING, Constants::TaskStatuses::ERROR] => Constants::TaskEvents::FAILED,

            [Constants::TaskStatuses::IN_PROGRESS,
             Constants::TaskStatuses::PENDING] => Constants::TaskEvents::INITIALIZE_REQUESTED,
            [Constants::TaskStatuses::IN_PROGRESS,
             Constants::TaskStatuses::COMPLETE] => Constants::TaskEvents::COMPLETED,
            [Constants::TaskStatuses::IN_PROGRESS, Constants::TaskStatuses::ERROR] => Constants::TaskEvents::FAILED,
            [Constants::TaskStatuses::IN_PROGRESS,
             Constants::TaskStatuses::CANCELLED] => Constants::TaskEvents::CANCELLED,

            [Constants::TaskStatuses::ERROR,
             Constants::TaskStatuses::PENDING] => Constants::TaskEvents::RETRY_REQUESTED,
            [Constants::TaskStatuses::ERROR,
             Constants::TaskStatuses::RESOLVED_MANUALLY] => Constants::TaskEvents::RESOLVED_MANUALLY,

            # New transitions for admin override scenarios
            [Constants::TaskStatuses::COMPLETE, Constants::TaskStatuses::CANCELLED] => Constants::TaskEvents::CANCELLED,
            [Constants::TaskStatuses::RESOLVED_MANUALLY,
             Constants::TaskStatuses::CANCELLED] => Constants::TaskEvents::CANCELLED
          }.freeze
        end

        # Class-level wrapper methods for guard clause context
        # These delegate to instance methods to provide clean access from guard clauses

        # Check if a transition is idempotent (current state == target state)
        #
        # @param task [Task] The task to check
        # @param target_state [String] The target state
        # @return [Boolean] True if this is an idempotent transition
        def idempotent_transition?(task, target_state)
          effective_state = effective_current_state(task)
          is_idempotent = effective_state == target_state

          if is_idempotent
            Rails.logger.debug do
              "TaskStateMachine: Detected idempotent transition to #{target_state} for task #{task.task_id}"
            end
          end

          is_idempotent
        end

        # Get the effective current state, handling blank/empty states
        #
        # @param task [Task] The task to check
        # @return [String] The effective current state (blank states become PENDING)
        def effective_current_state(task)
          current_state = task.state_machine.current_state
          current_state.presence || Constants::TaskStatuses::PENDING
        end

        # Safely fire a lifecycle event using dry-events bus
        #
        # @param event_name [String] The event name
        # @param context [Hash] The event context
        # @return [void]
        def safe_fire_event(event_name, context = {})
          publish_event(event_name, context)
        end

        # Determine the transition event name based on states using hashmap lookup
        #
        # @param from_state [String] The from state
        # @param to_state [String] The to state
        # @return [String, nil] The event name or nil if no mapping exists
        def determine_transition_event_name(from_state, to_state)
          transition_key = [from_state, to_state]
          event_name = transition_event_map[transition_key]

          if event_name.nil?
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
            # Use state_machine.current_state to avoid circular reference with step.status
            current_state = step.state_machine.current_state
            step_status = current_state.presence || Constants::WorkflowStepStatuses::PENDING
            incomplete_statuses.include?(step_status)
          end
        rescue StandardError => e
          # If there's an error checking steps, log it and assume no incomplete steps
          # This prevents step checking from blocking task completion in edge cases
          Rails.logger.warn do
            "TaskStateMachine: Error checking steps for task #{task.task_id}: #{e.message}. " \
              'Assuming no incomplete steps.'
          end
          false
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
