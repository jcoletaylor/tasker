# frozen_string_literal: true

# Example JWT Authenticator for Tasker
#
# This demonstrates how to implement JWT-based authentication that works with Tasker.
# In a real application, you would:
# 1. Install the 'jwt' gem: `gem 'jwt'`
# 2. Configure your JWT secret and algorithm
# 3. Set up user model integration
# 4. Handle token refresh logic as needed
#
# Usage in Tasker configuration:
#   Tasker::Configuration.configuration do |config|
#     config.auth do |auth|
#       auth.strategy = :custom
#       auth.options = {
#         authenticator_class: 'ExampleJWTAuthenticator',
#         secret: Rails.application.credentials.jwt_secret,
#         algorithm: 'HS256',
#         header_name: 'Authorization',
#         user_class: 'User'
#       }
#     end
#   end

require 'jwt'

class ExampleJWTAuthenticator
  include Tasker::Authentication::Interface

  def initialize(options = {})
    @secret = options[:secret]
    @algorithm = options[:algorithm] || 'HS256'
    @header_name = options[:header_name] || 'Authorization'
    @user_class = options[:user_class] || 'User'
    @options = options
  end

  def authenticate!(controller)
    user = current_user(controller)
    unless user
      raise Tasker::Authentication::AuthenticationError,
            'Invalid or missing JWT token'
    end
    true
  end

  def current_user(controller)
    return @current_user if defined?(@current_user)

    @current_user = begin
      token = extract_token(controller.request)
      return nil unless token

      payload = decode_token(token)
      return nil unless payload

      find_user(payload)
    rescue JWT::DecodeError => e
      Rails.logger.warn "JWT decode error: #{e.message}" if defined?(Rails)
      nil
    rescue StandardError => e
      Rails.logger.error "JWT authentication error: #{e.message}" if defined?(Rails)
      nil
    end
  end

  def authenticated?(controller)
    current_user(controller).present?
  end

  def validate_configuration(options = {})
    errors = []

    # Validate JWT secret
    secret = options[:secret]
    if secret.blank?
      errors << 'JWT secret is required'
    elsif secret.length < 32
      errors << 'JWT secret should be at least 32 characters for security'
    end

    # Validate algorithm
    algorithm = options[:algorithm] || 'HS256'
    allowed_algorithms = %w[HS256 HS384 HS512 RS256 RS384 RS512 ES256 ES384 ES512]
    unless allowed_algorithms.include?(algorithm)
      errors << "JWT algorithm must be one of: #{allowed_algorithms.join(', ')}"
    end

    # Validate user class exists
    user_class = options[:user_class] || 'User'
    begin
      user_class.constantize
    rescue NameError
      errors << "User class '#{user_class}' not found"
    end

    # Check if JWT gem is available
    begin
      require 'jwt'
    rescue LoadError
      errors << "JWT gem is required. Add 'gem \"jwt\"' to your Gemfile"
    end

    errors
  end

  private

  attr_reader :secret, :algorithm, :header_name, :user_class, :options

  def extract_token(request)
    header = request.headers[header_name]
    return nil if header.blank?

    # Support both "Bearer <token>" and raw token formats
    if header.start_with?('Bearer ')
      header.sub(/^Bearer /, '')
    else
      header
    end
  end

  def decode_token(token)
    # Decode and verify the JWT token
    payload, _header = JWT.decode(
      token,
      secret,
      true, # verify signature
      {
        algorithm: algorithm,
        verify_expiration: true,
        verify_iat: true # issued at time
      }
    )

    payload
  rescue JWT::ExpiredSignature
    Rails.logger.info 'JWT token expired' if defined?(Rails)
    nil
  rescue JWT::InvalidIatError
    Rails.logger.warn 'JWT token has invalid issued at time' if defined?(Rails)
    nil
  end

  def find_user(payload)
    # Extract user ID from JWT payload
    user_id = payload['user_id'] || payload['sub']
    return nil unless user_id

    # Look up user in database
    user_model = user_class.constantize

    if user_model.respond_to?(:find_by)
      user_model.find_by(id: user_id)
    else
      # Fallback for models without find_by
      user_model.where(id: user_id).first
    end
  rescue ActiveRecord::RecordNotFound, NoMethodError
    nil
  end

  # Helper method for generating test tokens (not for production use)
  def self.generate_test_token(user_id:, secret:, algorithm: 'HS256', expires_in: 1.hour)
    payload = {
      user_id: user_id,
      exp: (Time.current + expires_in).to_i,
      iat: Time.current.to_i,
      iss: 'tasker-test',  # issuer
      aud: 'tasker-api'    # audience
    }

    JWT.encode(payload, secret, algorithm)
  end
end

# Mock User class for testing JWT authenticator
class JwtTestUser
  attr_accessor :id, :email, :name, :roles

  def initialize(attributes = {})
    @id = attributes[:id] || attributes['id']
    @email = attributes[:email] || attributes['email'] || 'test@example.com'
    @name = attributes[:name] || attributes['name'] || 'Test User'
    @roles = attributes[:roles] || attributes['roles'] || []
  end

  def self.find_by(conditions)
    # Simulate database lookup
    return unless conditions[:id]

    case conditions[:id].to_i
    when 1
      new(id: 1, email: 'alice@example.com', name: 'Alice Smith', roles: ['user'])
    when 2
      new(id: 2, email: 'bob@example.com', name: 'Bob Jones', roles: ['admin'])
    when 999
      new(id: 999, email: 'admin@example.com', name: 'Super Admin', roles: %w[admin super_admin])
    end
  end

  def admin?
    roles.include?('admin')
  end

  def present?
    true
  end
end
