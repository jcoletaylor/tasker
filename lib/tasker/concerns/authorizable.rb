# frozen_string_literal: true

module Tasker
  module Concerns
    # Authorizable concern for user models to integrate with Tasker authorization.
    #
    # This concern provides a standard interface that user models can include
    # to work with the Tasker authorization system. It defines conventional
    # methods for checking permissions, roles, and admin status.
    #
    # The concern is designed to be flexible and work with different
    # authorization systems by providing sensible defaults that can be
    # overridden as needed.
    #
    # @example Basic usage
    #   class User < ApplicationRecord
    #     include Tasker::Concerns::Authorizable
    #   end
    #
    # @example Customized configuration
    #   class User < ApplicationRecord
    #     include Tasker::Concerns::Authorizable
    #
    #     configure_tasker_authorization(
    #       permission_method: :can_do?,
    #       role_method: :user_roles,
    #       admin_method: :is_admin?
    #     )
    #   end
    module Authorizable
      extend ActiveSupport::Concern

      included do
        # This concern provides a standard interface for authorization
        # The implementing class should define permission-checking methods
        # or use the provided defaults
      end

      class_methods do
        # Get the current authorization configuration for this class
        #
        # @return [Hash] Configuration hash with method names
        def tasker_authorizable_config
          @tasker_authorizable_config ||= {
            permission_method: :has_tasker_permission?,
            role_method: :tasker_roles,
            admin_method: :tasker_admin?
          }
        end

        # Configure the authorization method names for this class
        #
        # This allows you to customize which methods are called for
        # authorization checks, making it easier to integrate with
        # existing authorization systems.
        #
        # @param options [Hash] Configuration options
        # @option options [Symbol] :permission_method Method to check permissions
        # @option options [Symbol] :role_method Method to get user roles
        # @option options [Symbol] :admin_method Method to check admin status
        def configure_tasker_authorization(options = {})
          tasker_authorizable_config.merge!(options)
        end
      end

      # Check if the user has a specific permission
      #
      # This is the primary method for checking permissions. The default
      # implementation looks for a `permissions` method on the user object.
      # Override this method to integrate with your authorization system.
      #
      # @param permission [String] Permission string (e.g., "tasker.task:show")
      # @return [Boolean] True if the user has the permission
      def has_tasker_permission?(permission)
        # Use configured method or default logic
        permission_method = self.class.tasker_authorizable_config[:permission_method]

        if permission_method != :has_tasker_permission? && respond_to?(permission_method)
          send(permission_method, permission)
        elsif respond_to?(:permissions)
          permissions_list = permissions
          permissions_list&.include?(permission) || false
        else
          false
        end
      end

      # Get the user's roles
      #
      # This method should return an array of role names/identifiers.
      # The default implementation looks for a `roles` method.
      #
      # @return [Array] Array of user roles
      def tasker_roles
        # Use configured method or default logic
        role_method = self.class.tasker_authorizable_config[:role_method]

        if role_method != :tasker_roles && respond_to?(role_method)
          send(role_method) || []
        elsif respond_to?(:roles)
          roles || []
        else
          []
        end
      end

      # Check if the user is an admin
      #
      # This method checks for admin status using common patterns.
      # Override this method if your application uses different admin detection.
      #
      # @return [Boolean] True if the user is an admin
      def tasker_admin?
        # Use configured method or default logic
        admin_method = self.class.tasker_authorizable_config[:admin_method]

        if admin_method != :tasker_admin? && respond_to?(admin_method)
          send(admin_method) || false
        elsif respond_to?(:admin?) && admin?
          true
        elsif respond_to?(:role) && role == 'admin'
          true
        elsif tasker_roles.include?('admin')
          true
        else
          false
        end
      end

      # Get permissions for a specific resource
      #
      # This method returns an array of actions the user can perform
      # on a specific resource. Override this method to provide
      # resource-specific permission logic.
      #
      # @param resource [String] The resource name (e.g., 'tasker.task')
      # @return [Array<Symbol>] Array of permitted actions
      def tasker_permissions_for_resource(resource)
        # Default: return all actions for the resource if user has any permissions
        resource_config = Tasker::Authorization::ResourceRegistry.resources[resource]
        return [] unless resource_config

        resource_config[:actions].select do |action|
          has_tasker_permission?("#{resource}:#{action}")
        end
      end

      # Check if user can perform any actions on a resource
      #
      # @param resource [String] The resource name
      # @return [Boolean] True if user has any permissions for the resource
      def can_access_tasker_resource?(resource)
        tasker_permissions_for_resource(resource).any?
      end

      # Get all Tasker permissions for this user
      #
      # This method returns all permissions the user has that are
      # related to Tasker resources.
      #
      # @return [Array<String>] Array of permission strings
      def all_tasker_permissions
        all_permissions = Tasker::Authorization::ResourceRegistry.all_permissions
        all_permissions.select { |permission| has_tasker_permission?(permission) }
      end
    end
  end
end
