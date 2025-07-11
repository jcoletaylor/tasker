# frozen_string_literal: true

# Require all authorization components
require_relative 'authorization/errors'
require_relative 'authorization/resource_constants'
require_relative 'authorization/resource_registry'
require_relative 'authorization/base_coordinator'

module Tasker
  # Authorization module providing resource-based authorization for Tasker.
  #
  # This module implements a flexible, configuration-driven authorization system
  # that follows the same dependency injection pattern as the authentication system.
  # It provides:
  #
  # - Resource-based permissions using "resource:action" patterns
  # - Pluggable authorization coordinators for custom logic
  # - Automatic controller integration via concerns
  # - User model integration via the Authorizable concern
  #
  # @example Basic configuration
  #   Tasker::Configuration.configuration do |config|
  #     config.auth do |auth|
  #       auth.enabled = true
  #       auth.coordinator_class = 'MyAuthorizationCoordinator'
  #       auth.user_class = 'User'
  #     end
  #   end
  #
  # @example Custom authorization coordinator
  #   class MyAuthorizationCoordinator < Tasker::Authorization::BaseCoordinator
  #     protected
  #
  #     def authorized?(resource, action, context = {})
  #       case resource
  #       when 'tasker.task'
  #         user.can_manage_tasks?
  #       else
  #         false
  #       end
  #     end
  #   end
  module Authorization
    # Get all available resources and their actions
    #
    # @return [Hash] Resource registry
    def self.resources
      ResourceRegistry.resources
    end

    # Get all available permissions in "resource:action" format
    #
    # @return [Array<String>] All available permissions
    def self.all_permissions
      ResourceRegistry.all_permissions
    end

    # Check if a resource exists
    #
    # @param resource [String] Resource name
    # @return [Boolean] True if resource exists
    def self.resource_exists?(resource)
      ResourceRegistry.resource_exists?(resource)
    end

    # Check if an action exists for a resource
    #
    # @param resource [String] Resource name
    # @param action [Symbol, String] Action name
    # @return [Boolean] True if action exists for the resource
    def self.action_exists?(resource, action)
      ResourceRegistry.action_exists?(resource, action)
    end
  end
end
