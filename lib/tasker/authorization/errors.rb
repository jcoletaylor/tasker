# frozen_string_literal: true

module Tasker
  module Authorization
    # Base error class for all authorization-related errors
    class AuthorizationError < StandardError; end

    # Raised when a user is not authorized to perform a specific action
    #
    # This error should be raised when authorization checks fail, typically
    # resulting in a 403 Forbidden HTTP response.
    #
    # @example
    #   raise UnauthorizedError, "Not authorized to delete task 123"
    class UnauthorizedError < AuthorizationError; end

    # Raised when authorization configuration is invalid
    #
    # This error indicates problems with the authorization setup, such as
    # missing coordinator classes or invalid configuration options.
    #
    # @example
    #   raise ConfigurationError, "Authorization coordinator class 'InvalidClass' not found"
    class ConfigurationError < AuthorizationError; end
  end
end
