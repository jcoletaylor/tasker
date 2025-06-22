# frozen_string_literal: true

module Tasker
  module Types
    # Configuration type for health check settings
    #
    # This configuration handles health check endpoint behavior and authentication requirements.
    # It provides the same functionality as the original HealthConfiguration but with
    # dry-struct type safety and immutability.
    #
    # @example Basic usage
    #   config = HealthConfig.new(
    #     status_requires_authentication: false,
    #     readiness_timeout_seconds: 10.0
    #   )
    #
    # @example Full configuration
    #   config = HealthConfig.new(
    #     status_endpoint_requires_auth: true,
    #     ready_requires_authentication: false,
    #     status_requires_authentication: true,
    #     readiness_timeout_seconds: 5.0,
    #     cache_duration_seconds: 15
    #   )
    class HealthConfig < BaseConfig
      transform_keys(&:to_sym)

      # Custom boolean type that accepts various truthy/falsy values
      BooleanType = Types::Bool.constructor do |value|
        case value
        when true, 'true', 'yes', '1', 1
          true
        when false, 'false', 'no', '0', 0, nil, ''
          false
        else
          !value.nil? # Convert any other truthy value to true, falsy to false
        end
      end

      # Whether status endpoint requires authentication (backward compatibility)
      #
      # @!attribute [r] status_endpoint_requires_auth
      #   @return [Boolean] Whether status endpoint requires auth
      attribute :status_endpoint_requires_auth, BooleanType.default(true)

      # Whether ready endpoint requires authentication (K8s compatibility)
      #
      # @!attribute [r] ready_requires_authentication
      #   @return [Boolean] Whether ready endpoint requires authentication
      attribute :ready_requires_authentication, BooleanType.default(false)

      # Whether status endpoint requires authentication
      #
      # @!attribute [r] status_requires_authentication
      #   @return [Boolean] Whether status endpoint requires authentication
      attribute :status_requires_authentication, BooleanType.default(true)

      # Timeout for readiness checks in seconds
      #
      # @!attribute [r] readiness_timeout_seconds
      #   @return [Float] Readiness check timeout in seconds
      attribute :readiness_timeout_seconds, Types::Float.constrained(gt: 0).default(5.0)

      # Cache duration for status data in seconds
      #
      # @!attribute [r] cache_duration_seconds
      #   @return [Integer] Cache duration in seconds
      attribute :cache_duration_seconds, Types::Integer.constrained(gt: 0).default(15)

      # Validate health configuration settings
      #
      # This method maintains compatibility with the original HealthConfiguration
      # but is largely redundant since dry-struct handles validation automatically.
      #
      # @return [true] if valid
      # @raise [StandardError] if invalid configuration found
      def validate!
        # dry-struct automatically validates types and constraints
        # This method is kept for backward compatibility
        true
      end
    end
  end
end
