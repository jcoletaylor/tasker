# frozen_string_literal: true

require_relative 'errors'
require_relative 'none_authenticator'

module Tasker
  module Authentication
    class Coordinator
      class << self
        def authenticator
          @authenticator ||= build_authenticator
        end

        delegate :authenticate!, to: :authenticator

        delegate :current_user, to: :authenticator

        delegate :authenticated?, to: :authenticator

        def reset!
          @authenticator = nil
        end

        private

        def build_authenticator
          auth_config = Tasker::Configuration.configuration.auth

          if auth_config.authentication_enabled
            build_custom_authenticator(auth_config)
          else
            NoneAuthenticator.new
          end
        end

        def build_custom_authenticator(auth_config)
          authenticator_class = auth_config.authenticator_class

          unless authenticator_class
            raise ConfigurationError,
                  'Authentication is enabled but no authenticator_class is specified'
          end

          # Instantiate the host app's authenticator
          klass = authenticator_class.constantize
          # Pass empty options hash for now - authenticators can get config from Tasker::Configuration.configuration
          authenticator = klass.new({})

          # Validate it implements the interface
          validate_authenticator!(authenticator)

          authenticator
        end

        def validate_authenticator!(authenticator)
          required_methods = %i[authenticate! current_user]

          required_methods.each do |method|
            unless authenticator.respond_to?(method)
              raise InterfaceError,
                    "Authenticator #{authenticator.class} must implement ##{method}"
            end
          end

          # Run configuration validation if supported
          return unless authenticator.respond_to?(:validate_configuration)

          # Pass configuration options for validation - authenticators can extract what they need
          errors = authenticator.validate_configuration({})
          return unless errors.any?

          raise ConfigurationError,
                "Authenticator configuration errors: #{errors.join(', ')}"
        end
      end
    end
  end
end
