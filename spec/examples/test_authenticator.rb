# frozen_string_literal: true

# Test authenticator for use in specs
# Allows configuring different authentication scenarios for testing
class TestAuthenticator
  include Tasker::Authentication::Interface

  class << self
    attr_accessor :current_user_instance, :should_authenticate, :validation_errors

    def reset!
      @current_user_instance = nil
      @should_authenticate = true
      @validation_errors = []
    end

    # Configure what current_user should return
    def set_current_user(user)
      @current_user_instance = user
    end

    # Configure whether authentication should succeed or fail
    def set_authentication_result(success)
      @should_authenticate = success
    end

    # Configure validation errors to return
    def set_validation_errors(errors)
      @validation_errors = Array(errors)
    end
  end

  def initialize(options = {})
    @options = options
  end

  def authenticate!(_controller)
    unless self.class.should_authenticate
      raise Tasker::Authentication::AuthenticationError, 'Test authentication failed'
    end

    true
  end

  def current_user(_controller)
    self.class.current_user_instance
  end

  def authenticated?(controller)
    current_user(controller).present?
  end

  def validate_configuration(_options = {})
    self.class.validation_errors || []
  end

  private

  attr_reader :options
end

# Mock user class for testing
class TestUser
  attr_accessor :id, :name, :roles, :permissions

  def initialize(attributes = {})
    @id = attributes[:id] || 1
    @name = attributes[:name] || 'Test User'
    @roles = attributes[:roles] || []
    @permissions = attributes[:permissions] || []
  end

  def admin?
    roles.include?('admin')
  end

  def has_permission?(permission)
    permissions.include?(permission)
  end
end
