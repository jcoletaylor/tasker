# frozen_string_literal: true

module Tasker
  module Authentication
    # Interface that host application authenticators must implement
    module Interface
      # Required: Authenticate the request, raise exception if fails
      # @param controller [ActionController::Base] The controller instance
      # @return [void] Should raise exception on authentication failure
      def authenticate!(controller)
        raise NotImplementedError, 'Authenticator must implement #authenticate!'
      end

      # Required: Get the current authenticated user
      # @param controller [ActionController::Base] The controller instance
      # @return [Object, nil] The authenticated user object or nil
      def current_user(controller)
        raise NotImplementedError, 'Authenticator must implement #current_user'
      end

      # Optional: Check if user is authenticated (uses current_user by default)
      # @param controller [ActionController::Base] The controller instance
      # @return [Boolean] true if authenticated, false otherwise
      def authenticated?(controller)
        current_user(controller).present?
      end

      # Optional: Configuration validation for the authenticator
      # @param options [Hash] Configuration options
      # @return [Array<String>] Array of validation error messages, empty if valid
      def validate_configuration(_options = {})
        []
      end
    end
  end
end
