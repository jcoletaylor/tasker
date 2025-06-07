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
          auth_config = Tasker.configuration.auth

          case auth_config.strategy
          when :none
            NoneAuthenticator.new
          when :custom
            build_custom_authenticator(auth_config)
          else
            raise ConfigurationError,
                  "Unsupported authentication strategy: #{auth_config.strategy}. " \
                  'Use :none or :custom with authenticator_class option.'
          end
        end

        def build_custom_authenticator(auth_config)
          authenticator_class = auth_config.options[:authenticator_class]

          unless authenticator_class
            raise ConfigurationError,
                  'Custom authentication strategy requires authenticator_class option'
          end

          # Instantiate the host app's authenticator
          klass = authenticator_class.constantize
          authenticator = klass.new(auth_config.options)

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

          errors = authenticator.validate_configuration(Tasker.configuration.auth.options)
          return unless errors.any?

          raise ConfigurationError,
                "Authenticator configuration errors: #{errors.join(', ')}"
        end
      end
    end
  end
end
