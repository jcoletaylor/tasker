# Tasker Authentication Guide

## Overview

Tasker provides a flexible, provider-agnostic authentication system that works with any Rails authentication solution. The system uses **dependency injection** to allow host applications to provide their own authentication logic while maintaining a clean interface contract.

## Key Benefits

- **Provider Agnostic**: Works with Devise, JWT, OmniAuth, custom authentication, or no authentication
- **Dependency Injection**: Host applications implement authenticators rather than building provider-specific code into Tasker
- **Interface Validation**: Ensures authenticators implement required methods with helpful error messages
- **Configuration Validation**: Built-in validation with security best practices
- **Flexible Configuration**: Support for multiple strategies and environment-specific settings

## Table of Contents

- [Quick Start](#quick-start)
- [Authenticator Generator](#authenticator-generator)
- [Configuration Options](#configuration-options)
- [Authentication Strategies](#authentication-strategies)
- [Building Custom Authenticators](#building-custom-authenticators)
- [JWT Authentication Example](#jwt-authentication-example)
- [Integration with Controllers](#integration-with-controllers)
- [Error Handling](#error-handling)
- [Testing Authentication](#testing-authentication)
- [Best Practices](#best-practices)

## Quick Start

### 1. No Authentication (Default)

By default, Tasker requires no authentication:

```ruby
# config/initializers/tasker.rb
Tasker.configuration do |config|
  config.auth do |auth|
    auth.strategy = :none  # Default - no configuration needed
  end
end
```

### 2. Custom Authentication

For any authentication system, use the `:custom` strategy:

```ruby
# config/initializers/tasker.rb
Tasker.configuration do |config|
  config.auth do |auth|
    auth.strategy = :custom
    auth.options = {
      authenticator_class: 'YourCustomAuthenticator'
      # Additional options specific to your authenticator
    }
  end
end
```

## Authenticator Generator

Tasker provides a Rails generator to quickly create authenticator templates for common authentication systems:

### Basic Usage

```bash
# Generate a JWT authenticator
rails generate tasker:authenticator CompanyJWT --type=jwt

# Generate a Devise authenticator
rails generate tasker:authenticator AdminAuth --type=devise --user-class=Admin

# Generate an API token authenticator
rails generate tasker:authenticator ApiAuth --type=api_token

# Generate an OmniAuth authenticator
rails generate tasker:authenticator SocialAuth --type=omniauth

# Generate a custom authenticator template
rails generate tasker:authenticator CustomAuth --type=custom
```

### Generator Options

- `--type`: Authenticator type (jwt, devise, api_token, omniauth, custom)
- `--user-class`: User model class name (default: User)
- `--directory`: Output directory (default: app/lib/authenticators)
- `--with-spec/--no-with-spec`: Generate spec file (default: true)

### What the Generator Creates

The generator creates:

1. **Authenticator Class**: Complete implementation with security best practices
2. **Spec File**: Comprehensive test suite with example test cases
3. **Configuration Example**: Ready-to-use configuration for your initializer
4. **Usage Instructions**: Step-by-step setup guide with next steps

### Example: JWT Authenticator Generation

```bash
rails generate tasker:authenticator CompanyJWT --type=jwt --user-class=User
```

**Creates:**
- `app/lib/authenticators/company_jwt_authenticator.rb` - Full JWT implementation
- `spec/lib/authenticators/company_jwt_authenticator_spec.rb` - Test suite
- Configuration example and setup instructions

**Generated features:**
- JWT signature verification with configurable algorithms
- Bearer token and raw token support
- Comprehensive validation with security checks
- Test token generation helper for testing
- Memoized user lookup for performance

## Configuration Options

### Authentication Configuration Block

```ruby
Tasker.configuration do |config|
  config.auth do |auth|
    # Required: Authentication strategy
    auth.strategy = :none | :custom

    # Optional: Strategy-specific options
    auth.options = {
      authenticator_class: 'String',  # Required for :custom strategy
      # Additional options passed to your authenticator
    }
  end
end
```

### Configuration Validation

Tasker validates configuration at startup and provides helpful error messages:

```ruby
# Missing authenticator class
auth.strategy = :custom
auth.options = {}
# => ConfigurationError: "Custom authentication strategy requires authenticator_class option"

# Invalid authenticator class
auth.options = { authenticator_class: 'NonExistentClass' }
# => ConfigurationError: "Authenticator configuration errors: User class 'NonExistentClass' not found"
```

## Authentication Strategies

### `:none` Strategy

No authentication required. All users are considered "authenticated" with no user object.

```ruby
config.auth do |auth|
  auth.strategy = :none
end
```

**Use Cases:**
- Development environments
- Internal tools without user management
- Public APIs
- Testing scenarios

### `:custom` Strategy

Host application provides a custom authenticator class that implements the authentication interface.

```ruby
config.auth do |auth|
  auth.strategy = :custom
  auth.options = {
    authenticator_class: 'DeviseAuthenticator',
    scope: :user
  }
end
```

**Use Cases:**
- Devise integration
- JWT authentication
- OmniAuth integration
- Custom authentication systems
- Multi-tenant authentication

## Building Custom Authenticators

### Authentication Interface

All custom authenticators must implement the `Tasker::Authentication::Interface`:

```ruby
class YourCustomAuthenticator
  include Tasker::Authentication::Interface

  def initialize(options = {})
    # Initialize with configuration options
    @options = options
  end

  # Required: Authenticate the request, raise exception if fails
  def authenticate!(controller)
    # Implementation depends on your authentication system
    # Raise Tasker::Authentication::AuthenticationError if authentication fails
  end

  # Required: Get the current authenticated user
  def current_user(controller)
    # Return user object or nil
  end

  # Optional: Check if user is authenticated (uses current_user by default)
  def authenticated?(controller)
    current_user(controller).present?
  end

  # Optional: Configuration validation
  def validate_configuration(options = {})
    errors = []
    # Add validation logic, return array of error messages
    errors
  end

  private

  attr_reader :options
end
```

### Required Methods

#### `authenticate!(controller)`

**Purpose**: Authenticate the current request and raise an exception if authentication fails.

**Parameters**:
- `controller`: The Rails controller instance

**Behavior**:
- Must raise `Tasker::Authentication::AuthenticationError` if authentication fails
- Should return truthy value on success
- Called automatically by the `Authenticatable` concern

#### `current_user(controller)`

**Purpose**: Return the currently authenticated user object.

**Parameters**:
- `controller`: The Rails controller instance

**Returns**:
- User object if authenticated
- `nil` if not authenticated

**Notes**:
- Should be memoized for performance
- User object can be any class that represents your authenticated user

### Optional Methods

#### `authenticated?(controller)`

**Purpose**: Check if the current request is authenticated.

**Default Implementation**: Returns `current_user(controller).present?`

**Override**: When you need custom authentication logic beyond user presence.

#### `validate_configuration(options = {})`

**Purpose**: Validate authenticator-specific configuration options.

**Parameters**:
- `options`: Hash of configuration options

**Returns**: Array of error message strings (empty array if valid)

**Best Practices**:
- Check for required configuration options
- Validate external dependencies (gems, classes)
- Verify security settings (key lengths, algorithm choices)

## JWT Authentication Example

Our `ExampleJWTAuthenticator` demonstrates a production-ready JWT implementation:

### Basic Configuration

```ruby
# config/initializers/tasker.rb
Tasker.configuration do |config|
  config.auth do |auth|
    auth.strategy = :custom
    auth.options = {
      authenticator_class: 'ExampleJWTAuthenticator',
      secret: Rails.application.credentials.jwt_secret,
      algorithm: 'HS256',
      header_name: 'Authorization',
      user_class: 'User'
    }
  end
end
```

### Environment-Specific Configuration

```ruby
# config/initializers/tasker.rb
Tasker.configuration do |config|
  config.auth do |auth|
    auth.strategy = :custom
    auth.options = {
      authenticator_class: 'ExampleJWTAuthenticator',
      secret: Rails.env.production? ?
               Rails.application.credentials.jwt_secret :
               'development-secret-key-32-chars-min',
      algorithm: Rails.env.production? ? 'HS512' : 'HS256',
      user_class: 'User'
    }
  end
end
```

### Implementation Highlights

The `ExampleJWTAuthenticator` includes:

```ruby
class ExampleJWTAuthenticator
  include Tasker::Authentication::Interface

  def initialize(options = {})
    @secret = options[:secret]
    @algorithm = options[:algorithm] || 'HS256'
    @header_name = options[:header_name] || 'Authorization'
    @user_class = options[:user_class] || 'User'
  end

  def authenticate!(controller)
    user = current_user(controller)
    unless user
      raise Tasker::Authentication::AuthenticationError,
            "Invalid or missing JWT token"
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
    rescue JWT::DecodeError, StandardError
      nil
    end
  end

  def validate_configuration(options = {})
    errors = []

    # Validate JWT secret
    secret = options[:secret]
    if secret.blank?
      errors << "JWT secret is required"
    elsif secret.length < 32
      errors << "JWT secret should be at least 32 characters for security"
    end

    # Validate algorithm
    algorithm = options[:algorithm] || 'HS256'
    allowed_algorithms = %w[HS256 HS384 HS512 RS256 RS384 RS512 ES256 ES384 ES512]
    unless allowed_algorithms.include?(algorithm)
      errors << "JWT algorithm must be one of: #{allowed_algorithms.join(', ')}"
    end

    errors
  end

  private

  def extract_token(request)
    header = request.headers[@header_name]
    return nil unless header.present?

    # Support both "Bearer <token>" and raw token formats
    header.start_with?('Bearer ') ? header.sub(/^Bearer /, '') : header
  end

  def decode_token(token)
    payload, _header = JWT.decode(
      token,
      @secret,
      true,  # verify signature
      {
        algorithm: @algorithm,
        verify_expiration: true,
        verify_iat: true
      }
    )
    payload
  rescue JWT::ExpiredSignature, JWT::InvalidIatError
    nil
  end

  def find_user(payload)
    user_id = payload['user_id'] || payload['sub']
    return nil unless user_id

    user_model = @user_class.constantize
    user_model.find_by(id: user_id)
  rescue ActiveRecord::RecordNotFound, NoMethodError
    nil
  end
end
```

### Security Features

- **Signature Verification**: Validates JWT signatures to prevent tampering
- **Expiration Checking**: Automatically rejects expired tokens
- **Algorithm Validation**: Ensures only approved algorithms are used
- **Secret Length Validation**: Enforces minimum security standards
- **Error Handling**: Graceful handling of malformed or invalid tokens

## Integration with Controllers

### Automatic Integration

Controllers inherit authentication automatically from `ApplicationController`:

```ruby
# app/controllers/tasker/application_controller.rb
module Tasker
  class ApplicationController < ActionController::Base
    include Tasker::Concerns::Authenticatable
    # Authentication happens automatically via before_action
  end
end
```

### Available Helper Methods

In any Tasker controller, you have access to:

```ruby
class Tasker::TasksController < ApplicationController
  def index
    # Check if user is authenticated
    if tasker_user_authenticated?
      user = current_tasker_user  # Get current user object
      # ... authenticated logic
    else
      # ... handle unauthenticated scenario
    end
  end
end
```

### Controller Methods

- `current_tasker_user`: Returns the current user object (or nil)
- `tasker_user_authenticated?`: Returns boolean authentication status
- `authenticate_tasker_user!`: Manually trigger authentication (called automatically)

### GraphQL Integration

GraphQL endpoints also inherit authentication:

```ruby
# In GraphQL resolvers
def resolve(**args)
  user = context[:current_user]  # Available from authentication
  # ... resolver logic
end
```

## Error Handling

### Authentication Errors

The system provides standardized error handling:

```ruby
# HTTP Status Codes
401 Unauthorized  # Authentication required or failed
500 Internal Server Error  # Configuration or interface errors
```

### Error Types

```ruby
# Authentication failed
Tasker::Authentication::AuthenticationError
# => 401 Unauthorized response

# Invalid authenticator configuration
Tasker::Authentication::ConfigurationError
# => 500 Internal Server Error response

# Authenticator doesn't implement required interface
Tasker::Authentication::InterfaceError
# => 500 Internal Server Error response
```

### Custom Error Messages

Authenticators can provide meaningful error messages:

```ruby
def authenticate!(controller)
  token = extract_token(controller.request)

  unless token
    raise Tasker::Authentication::AuthenticationError,
          "Authorization header missing. Please provide a valid JWT token."
  end

  unless valid_token?(token)
    raise Tasker::Authentication::AuthenticationError,
          "Invalid JWT token. Please check your credentials and try again."
  end
end
```

## Testing Authentication

### Test Authenticator

For testing, use the provided `TestAuthenticator`:

```ruby
# spec/support/authentication_helper.rb
RSpec.configure do |config|
  config.before(:each) do
    # Reset authentication state
    TestAuthenticator.reset!
  end
end

# In tests
describe 'authenticated endpoint' do
  before do
    # Configure test authentication
    TestAuthenticator.set_authentication_result(true)
    TestAuthenticator.set_current_user(TestUser.new(id: 1, name: 'Test User'))
  end

  it 'allows access for authenticated users' do
    get '/tasker/tasks'
    expect(response).to have_http_status(:ok)
  end
end

describe 'unauthenticated access' do
  before do
    TestAuthenticator.set_authentication_result(false)
    TestAuthenticator.set_current_user(nil)
  end

  it 'denies access for unauthenticated users' do
    get '/tasker/tasks'
    expect(response).to have_http_status(:unauthorized)
  end
end
```

### JWT Testing

For JWT authenticator testing:

```ruby
# Generate test tokens
test_secret = 'test-secret-key-32-characters-plus'
user_token = ExampleJWTAuthenticator.generate_test_token(
  user_id: 1,
  secret: test_secret
)

# Use in request specs
headers = { 'Authorization' => "Bearer #{user_token}" }
get '/tasker/tasks', headers: headers
```

## Best Practices

### Security

1. **Use Strong Secrets**: Minimum 32 characters for JWT secrets
2. **Choose Secure Algorithms**: Prefer HS256/HS512 for HMAC, RS256+ for RSA
3. **Validate Configuration**: Implement `validate_configuration` for security checks
4. **Handle Errors Gracefully**: Never expose sensitive information in error messages
5. **Implement Token Expiration**: Always set reasonable expiration times

### Performance

1. **Memoize User Lookups**: Cache user objects within request scope
2. **Efficient Database Queries**: Use `find_by` instead of exceptions for user lookup
3. **Minimal Token Validation**: Only decode/validate tokens once per request

### Development

1. **Use Different Configs for Environments**: Separate dev/test/production settings
2. **Provide Clear Error Messages**: Help developers debug configuration issues
3. **Document Your Authenticator**: Include usage examples and configuration options
4. **Test Edge Cases**: Expired tokens, malformed headers, missing users

### Code Organization

```ruby
# Recommended file structure
app/
  lib/
    authenticators/
      devise_authenticator.rb
      jwt_authenticator.rb
      omniauth_authenticator.rb
  config/
    initializers/
      tasker.rb  # Authentication configuration
```

### Example Authenticator Template

```ruby
class YourAuthenticator
  include Tasker::Authentication::Interface

  def initialize(options = {})
    @options = options
    # Initialize your authenticator
  end

  def authenticate!(controller)
    # Your authentication logic
    user = current_user(controller)
    unless user
      raise Tasker::Authentication::AuthenticationError, "Authentication failed"
    end
    true
  end

  def current_user(controller)
    return @current_user if defined?(@current_user)

    @current_user = begin
      # Your user lookup logic
    rescue StandardError
      nil
    end
  end

  def validate_configuration(options = {})
    errors = []
    # Add your validation logic
    errors
  end

  private

  attr_reader :options

  # Your private helper methods
end
```

## Common Integration Patterns

### Devise Integration

```ruby
class DeviseAuthenticator
  include Tasker::Authentication::Interface

  def initialize(options = {})
    @scope = options[:scope] || :user
  end

  def authenticate!(controller)
    controller.send("authenticate_#{@scope}!")
  end

  def current_user(controller)
    controller.send("current_#{@scope}")
  end

  def validate_configuration(options = {})
    errors = []
    unless defined?(Devise)
      errors << "Devise gem is required for DeviseAuthenticator"
    end
    errors
  end

  private

  attr_reader :scope
end
```

### API Token Authentication

```ruby
class ApiTokenAuthenticator
  include Tasker::Authentication::Interface

  def initialize(options = {})
    @header_name = options[:header_name] || 'X-API-Token'
    @user_class = options[:user_class] || 'User'
  end

  def authenticate!(controller)
    user = current_user(controller)
    unless user
      raise Tasker::Authentication::AuthenticationError, "Invalid API token"
    end
    true
  end

  def current_user(controller)
    return @current_user if defined?(@current_user)

    @current_user = begin
      token = controller.request.headers[@header_name]
      return nil unless token

      user_class.constantize.find_by(api_token: token)
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end

  private

  attr_reader :header_name, :user_class
end
```

This authentication system provides the flexibility to integrate with any authentication solution while maintaining security, performance, and developer experience. The dependency injection pattern ensures that Tasker remains authentication-agnostic while providing a robust foundation for secure applications.
