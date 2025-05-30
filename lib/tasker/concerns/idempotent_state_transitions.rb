# frozen_string_literal: true

module Tasker
  module Concerns
    # IdempotentStateTransitions provides helper methods for safely transitioning
    # state machine objects without throwing errors on same-state transitions.
    #
    # This concern extracts the common pattern of checking current state before
    # attempting transitions to handle Statesman's restriction on same-state transitions.
    module IdempotentStateTransitions
      extend ActiveSupport::Concern

      # Safely transition a state machine object to a target state
      #
      # Checks the current state first and only attempts transition if different.
      # This prevents Statesman's "Cannot transition from X to X" errors.
      #
      # @param state_machine_object [Object] Object with a state_machine method
      # @param target_state [String] The desired target state
      # @param metadata [Hash] Optional metadata for the transition
      # @return [Boolean] True if transition occurred, false if already in target state
      def safe_transition_to(state_machine_object, target_state, metadata = {})
        current_state = state_machine_object.state_machine.current_state

        if current_state == target_state
          Rails.logger.debug do
            "#{self.class.name}: #{state_machine_object.class.name} #{state_machine_object.id} " \
              "already in #{target_state}, skipping transition"
          end
          return false
        end

        Rails.logger.debug do
          "#{self.class.name}: Transitioning #{state_machine_object.class.name} #{state_machine_object.id} " \
            "from #{current_state} to #{target_state}"
        end

        state_machine_object.state_machine.transition_to!(target_state, metadata)
        true
      rescue StandardError => e
        Rails.logger.error do
          "#{self.class.name}: Failed to transition #{state_machine_object.class.name} #{state_machine_object.id} " \
            "to #{target_state}: #{e.message}"
        end
        raise
      end

      # Safely transition to target state only if current state matches one of the allowed from states
      #
      # @param state_machine_object [Object] Object with a state_machine method
      # @param target_state [String] The desired target state
      # @param allowed_from_states [Array<String>] States from which transition is allowed
      # @param metadata [Hash] Optional metadata for the transition
      # @return [Symbol] :transitioned, :already_target, :invalid_from_state
      def conditional_transition_to(state_machine_object, target_state, allowed_from_states, metadata = {})
        current_state = state_machine_object.state_machine.current_state

        # Already in target state - idempotent
        return :already_target if current_state == target_state

        # Check if current state allows this transition
        unless allowed_from_states.include?(current_state)
          Rails.logger.debug do
            "#{self.class.name}: Cannot transition #{state_machine_object.class.name} #{state_machine_object.id} " \
              "from #{current_state} to #{target_state}. Allowed from states: #{allowed_from_states.join(', ')}"
          end
          return :invalid_from_state
        end

        # Perform the transition
        state_machine_object.state_machine.transition_to!(target_state, metadata)
        Rails.logger.debug do
          "#{self.class.name}: Successfully transitioned #{state_machine_object.class.name} #{state_machine_object.id} " \
            "from #{current_state} to #{target_state}"
        end
        :transitioned
      rescue StandardError => e
        Rails.logger.error do
          "#{self.class.name}: Failed to transition #{state_machine_object.class.name} #{state_machine_object.id} " \
            "to #{target_state}: #{e.message}"
        end
        raise
      end

      # Get current state safely, handling cases where state machine might not exist
      #
      # @param state_machine_object [Object] Object with a state_machine method
      # @return [String, nil] Current state or nil if no state machine
      def safe_current_state(state_machine_object)
        return nil unless state_machine_object.respond_to?(:state_machine)

        state_machine_object.state_machine.current_state
      rescue StandardError => e
        Rails.logger.warn do
          "#{self.class.name}: Could not get current state for #{state_machine_object.class.name} " \
            "#{state_machine_object.id}: #{e.message}"
        end
        nil
      end

      # Check if an object is in any of the specified states
      #
      # @param state_machine_object [Object] Object with a state_machine method
      # @param states [Array<String>] States to check against
      # @return [Boolean] True if current state is in the provided states
      def in_any_state?(state_machine_object, states)
        current_state = safe_current_state(state_machine_object)
        return false if current_state.nil?

        states.include?(current_state)
      end
    end
  end
end
