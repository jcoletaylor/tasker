# frozen_string_literal: true

module Tasker
  module Types
    # Configuration type for authentication and authorization settings
    #
    # This configuration handles all authentication and authorization settings for Tasker.
    # It provides the same functionality as the original AuthConfiguration but with
    # dry-struct type safety and immutability.
    #
    # @example Basic authentication setup
    #   config = AuthConfig.new(
    #     authentication_enabled: true,
    #     authenticator_class: 'MyAuthenticator',
    #     strategy: :custom
    #   )
    #
    # @example Full configuration
    #   config = AuthConfig.new(
    #     authentication_enabled: true,
    #     authenticator_class: 'JwtAuthenticator',
    #     current_user_method: :current_user,
    #     authenticate_user_method: :authenticate_user!,
    #     authorization_enabled: true,
    #     authorization_coordinator_class: 'MyAuthorizationCoordinator',
    #     user_class: 'User',
    #     strategy: :custom
    #   )
    class AuthConfig < BaseConfig
      transform_keys(&:to_sym)

      # Whether authentication is enabled
      #
      # @!attribute [r] authentication_enabled
      #   @return [Boolean] Whether authentication is enabled
      attribute :authentication_enabled, Types::Bool.default(false)

      # Class name for the authenticator (nil means no authentication)
      #
      # @!attribute [r] authenticator_class
      #   @return [String, nil] Class name for the authenticator
      attribute? :authenticator_class, Types::String.optional.default(nil)

      # Method name to get the current user
      #
      # @!attribute [r] current_user_method
      #   @return [Symbol] Method name to get the current user
      attribute :current_user_method, Types::Symbol.default(:current_user)

      # Method name to authenticate the user
      #
      # @!attribute [r] authenticate_user_method
      #   @return [Symbol] Method name to authenticate the user
      attribute :authenticate_user_method, Types::Symbol.default(:authenticate_user!)

      # Whether authorization is enabled
      #
      # @!attribute [r] authorization_enabled
      #   @return [Boolean] Whether authorization is enabled
      attribute :authorization_enabled, Types::Bool.default(false)

      # Class name for the authorization coordinator
      #
      # @!attribute [r] authorization_coordinator_class
      #   @return [String] Class name for the authorization coordinator
      attribute :authorization_coordinator_class, Types::String.default('Tasker::Authorization::BaseCoordinator')

      # Class name for the authorizable user class
      #
      # @!attribute [r] user_class
      #   @return [String, nil] Class name for the authorizable user class
      attribute? :user_class, Types::String.optional.default(nil)

      # Authentication strategy (:none, :test, :custom, etc.)
      #
      # @!attribute [r] strategy
      #   @return [Symbol] Authentication strategy
      attribute :strategy, Types::Symbol.default(:none)
    end
  end
end
