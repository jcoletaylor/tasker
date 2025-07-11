# frozen_string_literal: true

module Tasker
  module Concerns
    # Controller concern for automatic authorization integration.
    #
    # This concern provides automatic authorization for Tasker controllers
    # by adding a before_action that checks permissions before each action.
    # It follows the same pattern as the Authenticatable concern.
    #
    # The concern automatically extracts resource and action names from
    # the controller and action, then delegates to the configured
    # authorization coordinator for the actual authorization check.
    #
    # @example Basic usage
    #   class TasksController < ApplicationController
    #     include Tasker::Concerns::Authenticatable
    #     include Tasker::Concerns::ControllerAuthorizable
    #   end
    #
    # @example Skipping authorization for specific actions
    #   class TasksController < ApplicationController
    #     include Tasker::Concerns::ControllerAuthorizable
    #
    #     skip_before_action :authorize_tasker_action!, only: [:index]
    #   end
    module ControllerAuthorizable
      extend ActiveSupport::Concern

      included do
        # Add authorization check before each action
        before_action :authorize_tasker_action!, unless: :skip_authorization?
      end

      private

      # Perform the authorization check for the current action
      #
      # This method is called automatically before each controller action.
      # It extracts the resource and action names, builds the authorization
      # context, and delegates to the authorization coordinator.
      #
      # @return [true] When authorization succeeds
      # @raise [UnauthorizedError] When authorization fails
      def authorize_tasker_action!
        return true if skip_authorization?

        resource = tasker_resource_name
        action = tasker_action_name
        context = tasker_authorization_context

        authorization_coordinator.authorize!(resource, action, context)
      end

      # Get the authorization coordinator instance
      #
      # This method builds and memoizes the authorization coordinator
      # using the configured coordinator class and current user.
      #
      # @return [BaseCoordinator] The authorization coordinator instance
      def authorization_coordinator
        @authorization_coordinator ||= build_authorization_coordinator
      end

      # Build a new authorization coordinator instance
      #
      # @return [BaseCoordinator] New coordinator instance
      def build_authorization_coordinator
        coordinator_class = Tasker::Configuration.configuration.auth.authorization_coordinator_class.constantize
        coordinator_class.new(current_tasker_user)
      rescue NameError => e
        coordinator_class_name = Tasker::Configuration.configuration.auth.authorization_coordinator_class
        raise Tasker::Authorization::ConfigurationError,
              "Authorization coordinator class '#{coordinator_class_name}' not found: #{e.message}"
      end

      # Extract the resource name from the controller
      #
      # This method converts the controller name to a resource identifier
      # following the convention "tasker.{singular_controller_name}".
      #
      # @return [String] The resource name (e.g., "tasker.task")
      def tasker_resource_name
        # Extract controller name without the "Controller" suffix
        controller_name = self.class.name.demodulize.underscore.gsub('_controller', '')
        "tasker.#{controller_name.singularize}"
      end

      # Extract the action name from the current Rails action
      #
      # @return [Symbol] The action name (e.g., :show)
      def tasker_action_name
        action_name.to_sym
      end

      # Build the authorization context
      #
      # This method builds a context hash that provides additional
      # information for authorization decisions, such as resource IDs
      # and request parameters.
      #
      # @return [Hash] Authorization context
      def tasker_authorization_context
        {
          controller: self,
          params: params,
          resource_id: params[:id],
          parent_resource_id: params[:task_id],
          user: current_tasker_user
        }
      end

      # Check if authorization should be skipped for this request
      #
      # Authorization is skipped when:
      # - Authorization is disabled in configuration
      #
      # @return [Boolean] True if authorization should be skipped
      def skip_authorization?
        !Tasker::Configuration.configuration.auth.authorization_enabled
      end
    end
  end
end
