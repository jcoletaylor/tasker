# frozen_string_literal: true

module ConfigurationHelpers
  # Configure Tasker authentication and authorization using the new configuration style
  #
  # @param options [Hash] Configuration options
  # @option options [Boolean] :authentication_enabled (false) Enable authentication
  # @option options [String] :authenticator_class (nil) Authenticator class name
  # @option options [Boolean] :authorization_enabled (false) Enable authorization
  # @option options [String] :authorization_coordinator_class (nil) Authorization coordinator class name
  # @option options [String] :user_class (nil) User class name
  def configure_tasker_auth(
    authentication_enabled: false,
    authenticator_class: nil,
    authorization_enabled: false,
    authorization_coordinator_class: nil,
    user_class: nil
  )
    Tasker.configuration do |config|
      config.auth.authentication_enabled = authentication_enabled
      config.auth.authenticator_class = authenticator_class
      config.auth.authorization_enabled = authorization_enabled
      config.auth.authorization_coordinator_class = authorization_coordinator_class if authorization_coordinator_class
      config.auth.user_class = user_class if user_class
    end
  end

  # Legacy helper for backward compatibility with old configuration style
  # This will be deprecated in future versions
  def configure_tasker_auth_legacy(
    strategy: :none,
    options: {},
    enabled: false,
    coordinator_class: nil,
    user_class: nil
  )
    warn '[DEPRECATION] configure_tasker_auth_legacy is deprecated. Use configure_tasker_auth instead.'

    Tasker.configuration do |config|
      # Map old style to new style
      case strategy
      when :none
        config.auth.authentication_enabled = false
        config.auth.authenticator_class = nil
      when :custom
        config.auth.authentication_enabled = true
        config.auth.authenticator_class = options[:authenticator_class] || options['authenticator_class']
      end

      config.auth.authorization_enabled = enabled
      config.auth.authorization_coordinator_class = coordinator_class if coordinator_class
      config.auth.user_class = user_class if user_class
    end
  end
end

RSpec.configure do |config|
  config.include ConfigurationHelpers
end
