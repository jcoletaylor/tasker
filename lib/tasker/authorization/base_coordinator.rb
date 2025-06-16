# frozen_string_literal: true

module Tasker
  module Authorization
    # Base authorization coordinator providing the foundation for authorization logic.
    #
    # This class implements the core authorization interface that can be extended
    # by host applications to provide custom authorization logic. It follows the
    # same dependency injection pattern as the authentication system.
    #
    # Host applications should inherit from this class and implement the
    # `authorized?` method to provide their authorization logic.
    #
    # @example Basic usage
    #   coordinator = BaseCoordinator.new(current_user)
    #   coordinator.authorize!('tasker.task', :show, { task_id: 123 })
    #
    # @example Custom implementation
    #   class MyAuthorizationCoordinator < BaseCoordinator
    #     protected
    #
    #     def authorized?(resource, action, context = {})
    #       case resource
    #       when 'tasker.task'
    #         user.can_access_tasks?
    #       else
    #         false
    #       end
    #     end
    #   end
    class BaseCoordinator
      # Initialize the authorization coordinator
      #
      # @param user [Object, nil] The user object to authorize against
      def initialize(user = nil)
        @user = user
      end

      # Authorize an action and raise an exception if not permitted
      #
      # This method checks authorization and raises an UnauthorizedError
      # if the action is not permitted.
      #
      # @param resource [String] The resource being accessed (e.g., 'tasker.task')
      # @param action [Symbol, String] The action being performed (e.g., :show)
      # @param context [Hash] Additional context for authorization decisions
      # @raise [UnauthorizedError] When the action is not authorized
      # @return [true] When the action is authorized
      def authorize!(resource, action, context = {})
        unless can?(resource, action, context)
          raise UnauthorizedError,
                "Not authorized to #{action} on #{resource}"
        end

        true
      end

      # Check if an action is authorized
      #
      # This method performs the authorization check without raising an exception.
      # It validates the resource and action exist, then delegates to the
      # `authorized?` method for the actual authorization logic.
      #
      # @param resource [String] The resource being accessed
      # @param action [Symbol, String] The action being performed
      # @param context [Hash] Additional context for authorization decisions
      # @return [Boolean] True if the action is authorized
      def can?(resource, action, context = {})
        # Allow all actions if authorization is disabled
        return true unless authorization_enabled?

        # Validate resource and action exist in the registry
        unless ResourceRegistry.action_exists?(resource, action)
          raise ArgumentError, "Unknown resource:action '#{resource}:#{action}'"
        end

        # Delegate to subclass implementation
        authorized?(resource, action, context)
      end

      protected

      # Authorization logic to be implemented by subclasses
      #
      # This method should be overridden by host applications to provide
      # their specific authorization logic. The default implementation
      # denies all access.
      #
      # @param _resource [String] The resource being accessed (unused in base implementation)
      # @param _action [Symbol, String] The action being performed (unused in base implementation)
      # @param _context [Hash] Additional context for authorization decisions (unused in base implementation)
      # @return [Boolean] True if the action should be authorized
      def authorized?(_resource, _action, _context = {})
        # Default implementation: deny all access
        # Subclasses should override this method
        false
      end

      # Check if authorization is enabled in the configuration
      #
      # @return [Boolean] True if authorization is enabled
      def authorization_enabled?
        Tasker.configuration.auth.authorization_enabled
      end

      # The user object for authorization checks
      #
      # @return [Object, nil] The current user
      attr_reader :user
    end
  end
end
