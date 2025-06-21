# frozen_string_literal: true

module Tasker
  module Authorization
    # Constants for authorization resource names and actions.
    #
    # This module provides centralized constants for all authorization
    # resource identifiers, making the codebase more maintainable and
    # reducing the risk of typos in resource strings.
    #
    # @example Using resource constants
    #   coordinator.authorize!(RESOURCES::TASK, ACTIONS::SHOW)
    #   ResourceRegistry.resource_exists?(RESOURCES::WORKFLOW_STEP)
    module ResourceConstants
      # Resource name constants
      module RESOURCES
        TASK = 'tasker.task'
        WORKFLOW_STEP = 'tasker.workflow_step'
        TASK_DIAGRAM = 'tasker.task_diagram'
        HEALTH_STATUS = 'tasker.health_status'
        HANDLER = 'tasker.handler'

        # Get all resource constants as an array
        #
        # @return [Array<String>] All defined resource names
        def self.all
          [TASK, WORKFLOW_STEP, TASK_DIAGRAM, HEALTH_STATUS, HANDLER]
        end

        # Check if a resource constant is defined
        #
        # @param resource [String] Resource name to check
        # @return [Boolean] True if the resource is defined
        def self.include?(resource)
          all.include?(resource)
        end
      end

      # Common action constants used across resources
      module ACTIONS
        INDEX = :index
        SHOW = :show
        CREATE = :create
        UPDATE = :update
        DESTROY = :destroy
        RETRY = :retry
        CANCEL = :cancel

        # Standard CRUD actions
        #
        # @return [Array<Symbol>] Standard CRUD action symbols
        def self.crud
          [INDEX, SHOW, CREATE, UPDATE, DESTROY]
        end

        # Task-specific actions
        #
        # @return [Array<Symbol>] Actions specific to tasks
        def self.task_specific
          [RETRY, CANCEL]
        end

        # All defined actions
        #
        # @return [Array<Symbol>] All action constants
        def self.all
          [INDEX, SHOW, CREATE, UPDATE, DESTROY, RETRY, CANCEL]
        end
      end
    end
  end
end
