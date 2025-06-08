# frozen_string_literal: true

require_relative 'resource_constants'

module Tasker
  module Authorization
    # Resource registry defining available resources and their permitted actions
    # for authorization purposes.
    #
    # This registry serves as a central catalog of all resources that can be
    # authorized within the Tasker system. Each resource defines a set of
    # actions that can be performed on it.
    #
    # @example Checking if a resource exists
    #   ResourceRegistry.resource_exists?(RESOURCES::TASK) # => true
    #
    # @example Checking if an action is valid for a resource
    #   ResourceRegistry.action_exists?(RESOURCES::TASK, ACTIONS::SHOW) # => true
    #
    # @example Getting all available permissions
    #   ResourceRegistry.all_permissions
    #   # => ["tasker.task:index", "tasker.task:show", ...]
    class ResourceRegistry
      include ResourceConstants

      # Registry of all available resources and their permitted actions
      RESOURCES = {
        ResourceConstants::RESOURCES::TASK => {
          actions: [
            ResourceConstants::ACTIONS::INDEX,
            ResourceConstants::ACTIONS::SHOW,
            ResourceConstants::ACTIONS::CREATE,
            ResourceConstants::ACTIONS::UPDATE,
            ResourceConstants::ACTIONS::DESTROY,
            ResourceConstants::ACTIONS::RETRY,
            ResourceConstants::ACTIONS::CANCEL
          ],
          description: 'Tasker workflow tasks'
        },
        ResourceConstants::RESOURCES::WORKFLOW_STEP => {
          actions: [
            ResourceConstants::ACTIONS::INDEX,
            ResourceConstants::ACTIONS::SHOW,
            ResourceConstants::ACTIONS::UPDATE,
            ResourceConstants::ACTIONS::DESTROY,
            ResourceConstants::ACTIONS::RETRY,
            ResourceConstants::ACTIONS::CANCEL
          ],
          description: 'Individual workflow steps'
        },
        ResourceConstants::RESOURCES::TASK_DIAGRAM => {
          actions: [
            ResourceConstants::ACTIONS::INDEX,
            ResourceConstants::ACTIONS::SHOW
          ],
          description: 'Task workflow diagrams'
        }
      }.freeze

      class << self
        # Get all registered resources
        #
        # @return [Hash] The complete resource registry
        def resources
          RESOURCES
        end

        # Check if a resource exists in the registry
        #
        # @param resource [String] The resource name (e.g., 'tasker.task')
        # @return [Boolean] True if the resource exists
        def resource_exists?(resource)
          RESOURCES.key?(resource)
        end

        # Check if an action is valid for a given resource
        #
        # @param resource [String] The resource name
        # @param action [Symbol, String] The action name
        # @return [Boolean] True if the action exists for the resource
        def action_exists?(resource, action)
          return false unless resource_exists?(resource)

          RESOURCES[resource][:actions].include?(action.to_sym)
        end

        # Get all available permissions in "resource:action" format
        #
        # @return [Array<String>] All available permissions
        def all_permissions
          RESOURCES.flat_map do |resource, config|
            config[:actions].map { |action| "#{resource}:#{action}" }
          end
        end

        # Get all actions for a specific resource
        #
        # @param resource [String] The resource name
        # @return [Array<Symbol>] Available actions for the resource
        def actions_for_resource(resource)
          return [] unless resource_exists?(resource)

          RESOURCES[resource][:actions]
        end

        # Get description for a resource
        #
        # @param resource [String] The resource name
        # @return [String, nil] Description of the resource
        def resource_description(resource)
          return nil unless resource_exists?(resource)

          RESOURCES[resource][:description]
        end
      end
    end
  end
end
