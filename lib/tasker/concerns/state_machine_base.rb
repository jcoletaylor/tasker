# frozen_string_literal: true

require_relative 'event_publisher'

module Tasker
  module Concerns
    # StateMachineBase provides shared functionality for all Tasker state machines
    #
    # This concern consolidates common patterns used by TaskStateMachine and StepStateMachine:
    # - Idempotent transition handling
    # - Event publishing through unified publisher
    # - Consistent transition logging
    # - Helper methods for state checking
    #
    # It replaces the legacy LifecycleEvents system with direct integration to Events::Publisher
    module StateMachineBase
      extend ActiveSupport::Concern
      include EventPublisher

      included do
        # Common before_transition callback for idempotent handling
        before_transition do |object, transition|
          # Handle idempotent transitions using unified helper
          if StateMachineBase.idempotent_transition?(object, transition.to_state)
            raise Statesman::GuardFailedError, "Already in target state #{transition.to_state}"
          end

          # Log the transition for debugging
          effective_current_state = StateMachineBase.effective_current_state(object)
          object_id = StateMachineBase.object_id(object)
          Rails.logger.debug do
            "#{object.class.name} #{object_id} transitioning from #{effective_current_state} to #{transition.to_state}"
          end
        end

        # Common after_transition callback for event publishing
        after_transition do |object, transition|
          # Determine the appropriate event name based on the transition
          event_name = determine_transition_event_name(transition.from_state, transition.to_state)

          # Only fire the event if we have a valid event name
          if event_name
            # Build context appropriate for the object type
            context = StateMachineBase.build_event_context(object, transition)

            # Fire the event through unified publisher
            StateMachineBase.publish_event(event_name, context)
          end
        end
      end

      module ClassMethods
        # Check if a transition is idempotent (current state == target state)
        #
        # @param object [Object] The object with state_machine
        # @param target_state [String] The target state
        # @return [Boolean] True if this is an idempotent transition
        def idempotent_transition?(object, target_state)
          effective_state = effective_current_state(object)
          is_idempotent = effective_state == target_state

          if is_idempotent
            Rails.logger.debug do
              "#{object.class.name}: Detected idempotent transition to #{target_state} for #{object_id(object)}"
            end
          end

          is_idempotent
        end

        # Get the effective current state, handling blank/empty states
        #
        # @param object [Object] The object to check
        # @return [String] The effective current state (blank states become default)
        def effective_current_state(object)
          current_state = object.state_machine.current_state

          current_state.presence || case object.class.name
                                    when /Task/
                                      Constants::TaskStatuses::PENDING
                                    when /WorkflowStep/
                                      Constants::WorkflowStepStatuses::PENDING
                                    else
                                      current_state
                                    end
        end

        # Get a consistent object identifier for logging
        #
        # @param object [Object] The object
        # @return [String] The object identifier
        def object_id(object)
          case object.class.name
          when /Task/
            object.task_id
          when /WorkflowStep/
            object.workflow_step_id
          else
            object.id
          end
        end

        # Build event context appropriate for the object type
        #
        # @param object [Object] The object being transitioned
        # @param transition [Statesman::Transition] The transition
        # @return [Hash] Event context
        def build_event_context(object, transition)
          base_context = {
            from_state: transition.from_state,
            to_state: transition.to_state,
            transitioned_at: Time.zone.now
          }

          case object.class.name
          when /Task/
            base_context.merge(
              task_id: object.task_id,
              task_name: object.name,
              task_context: object.respond_to?(:context) ? object.context : nil
            )
          when /WorkflowStep/
            base_context.merge(
              task_id: object.task_id,
              step_id: object.workflow_step_id,
              step_name: object.name
            )
          else
            base_context.merge(
              object_id: object.id,
              object_type: object.class.name
            )
          end
        end

        # Publish event through unified Events::Publisher system
        # Uses the EventPublisher concern for consistent implementation
        #
        # @param event_name [String] The event name
        # @param context [Hash] The event context
        # @return [void]
        # Note: This method is provided by the EventPublisher concern

        # Log an invalid from-state transition
        #
        # @param object [Object] The object
        # @param current_state [String] The current state
        # @param target_state [String] The target state
        # @param reason [String] The reason for the restriction
        def log_invalid_from_state(object, current_state, target_state, reason)
          Rails.logger.debug do
            "#{name}: Cannot transition to #{target_state} from '#{current_state}' " \
              "(#{object.class.name} #{object_id(object)}). #{reason}."
          end
        end

        # Log when dependencies/conditions are not met
        #
        # @param object [Object] The object
        # @param target_state [String] The target state
        # @param reason [String] The specific reason
        def log_condition_not_met(object, target_state, reason)
          Rails.logger.debug do
            "#{name}: Cannot transition #{object.class.name} #{object_id(object)} to #{target_state} - #{reason}"
          end
        end

        # Log the result of a transition check
        #
        # @param object [Object] The object
        # @param target_state [String] The target state
        # @param result [Boolean] Whether the transition is allowed
        # @param reason [String] The reason for the result
        def log_transition_result(object, target_state, result, reason)
          object_identifier = "#{object.class.name} #{object_id(object)}"
          if result
            Rails.logger.debug do
              "#{name}: Allowing transition to #{target_state} for #{object_identifier} (#{reason})"
            end
          else
            Rails.logger.debug do
              "#{name}: Blocking transition to #{target_state} for #{object_identifier} (#{reason} failed)"
            end
          end
        end
      end

      # Access to class methods from instance methods
      module StateMachineBase
        module ClassMethods
          delegate :idempotent_transition?, to: :StateMachineBase

          delegate :effective_current_state, to: :StateMachineBase

          delegate :object_id, to: :StateMachineBase

          # Use EventPublisher for consistent event publishing
          def publish_event(event_name, context = {})
            # Create a temporary object to access the concern method
            publisher = Object.new.extend(EventPublisher)
            publisher.send(:publish_event, event_name, context)
          end
        end
      end

      private

      # Instance method is provided by EventPublisher concern
      # No need to override here

      # Instance method wrapper for determining transition event name
      # (To be implemented by including classes)
      def determine_transition_event_name(from_state, to_state)
        self.class.determine_transition_event_name(from_state, to_state)
      end
    end
  end
end
