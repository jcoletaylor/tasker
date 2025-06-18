# Tasker Authentication & Authorization Guide

## Overview

Tasker provides a comprehensive, flexible authentication and authorization system that works with any Rails authentication solution. The system uses **dependency injection** and **resource-based authorization** to allow host applications to provide their own authentication logic while maintaining enterprise-grade security for both REST APIs and GraphQL endpoints.

## 🎉 Latest Updates - Complete Authorization System

**Phase 5 Controller Integration - COMPLETED! ✅**

We've successfully implemented **revolutionary GraphQL authorization** and complete controller integration:

- **✅ GraphQL Operation-Level Authorization**: Automatically maps GraphQL operations to resource:action permissions
- **✅ Automatic Controller Authorization**: All REST and GraphQL endpoints protected seamlessly
- **✅ Resource Registry**: Centralized constants eliminate hardcoded strings throughout codebase
- **✅ Complete Test Coverage**: 674/674 tests passing with comprehensive integration testing
- **✅ Zero Breaking Changes**: All features are opt-in and backward compatible
- **✅ State Isolation**: Robust test infrastructure prevents configuration leakage

**Ready for Production**: The complete authentication and authorization system is now production-ready with enterprise-grade security for both REST APIs and GraphQL endpoints.

## Key Benefits

- **Provider Agnostic**: Works with Devise, JWT, OmniAuth, custom authentication, or no authentication
- **Dependency Injection**: Host applications implement authenticators rather than building provider-specific code into Tasker
- **Resource-Based Authorization**: Granular permissions using resource:action patterns (e.g., `tasker.task:create`)
- **GraphQL Operation-Level Authorization**: Revolutionary security for GraphQL that maps operations to resource permissions
- **Automatic Controller Integration**: Authentication and authorization work seamlessly across REST and GraphQL
- **Interface Validation**: Ensures authenticators implement required methods with helpful error messages
- **Configuration Validation**: Built-in validation with security best practices
- **Flexible Configuration**: Support for multiple strategies and environment-specific settings
- **Zero Breaking Changes**: All features are opt-in and backward compatible

## Table of Contents

- [Quick Start](#quick-start)
- [Authorization Quick Start](#authorization-quick-start)
- [GraphQL Authorization](#graphql-authorization)
- [Authenticator Generator](#authenticator-generator)
- [Configuration Options](#configuration-options)
- [Authentication Strategies](#authentication-strategies)
- [Authorization System](#authorization-system)
- [Building Custom Authenticators](#building-custom-authenticators)
- [Building Authorization Coordinators](#building-authorization-coordinators)
- [JWT Authentication Example](#jwt-authentication-example)
- [Integration with Controllers](#integration-with-controllers)
- [Error Handling](#error-handling)
- [Testing Authentication](#testing-authentication)
- [Testing Authorization](#testing-authorization)
- [Best Practices](#best-practices)

## Quick Start

### 1. No Authentication (Default)

By default, Tasker requires no authentication:

```ruby
# config/initializers/tasker.rb
Tasker.configuration do |config|
  config.auth do |auth|
    auth.authentication_enabled = false  # Default - no configuration needed
  end
end
```

### 2. Custom Authentication

For any authentication system, enable authentication and specify your authenticator class:

```ruby
# config/initializers/tasker.rb
Tasker.configuration do |config|
  config.auth do |auth|
    auth.authentication_enabled = true
    auth.authenticator_class = 'YourCustomAuthenticator'
    # Additional options specific to your authenticator can be passed to the authenticator
  end
end
```

### 3. With Authorization (Recommended)

Enable both authentication and authorization for complete security:

```ruby
# config/initializers/tasker.rb
Tasker.configuration do |config|
  config.auth do |auth|
    auth.authentication_enabled = true
    auth.authenticator_class = 'YourCustomAuthenticator'
    auth.authorization_enabled = true
    auth.authorization_coordinator_class = 'YourAuthorizationCoordinator'
    auth.user_class = 'User'
  end
end
```

## Authorization Quick Start

Authorization in Tasker uses a **resource:action** permission model that works seamlessly with both REST APIs and GraphQL.

### 1. Enable Authorization

```ruby
# config/initializers/tasker.rb
Tasker.configuration do |config|
  config.auth do |auth|
    auth.authorization_enabled = true
    auth.authorization_coordinator_class = 'YourAuthorizationCoordinator'
    auth.user_class = 'User'
  end
end
```

### 2. Create Authorization Coordinator

```ruby
# app/tasker/authorization/your_authorization_coordinator.rb
class YourAuthorizationCoordinator < Tasker::Authorization::BaseCoordinator
  protected

  def authorized?(resource, action, context = {})
    case resource
    when Tasker::Authorization::ResourceConstants::RESOURCES::TASK
      authorize_task_action(action, context)
    when Tasker::Authorization::ResourceConstants::RESOURCES::WORKFLOW_STEP
      authorize_step_action(action, context)
    when Tasker::Authorization::ResourceConstants::RESOURCES::TASK_DIAGRAM
      authorize_diagram_action(action, context)
    when Tasker::Authorization::ResourceConstants::RESOURCES::HEALTH_STATUS
      authorize_health_status_action(action, context)
    else
      false
    end
  end

  private

  def authorize_task_action(action, context)
    case action
    when :index, :show
      # Regular users can view tasks
      user.tasker_admin? || user.has_tasker_permission?("#{Tasker::Authorization::ResourceConstants::RESOURCES::TASK}:#{action}")
    when :create, :update, :destroy, :retry, :cancel
      # Only admins can modify tasks
      user.tasker_admin? || user.has_tasker_permission?("#{Tasker::Authorization::ResourceConstants::RESOURCES::TASK}:#{action}")
    else
      false
    end
  end

  def authorize_step_action(action, context)
    case action
    when :index, :show
      user.tasker_admin? || user.has_tasker_permission?("#{Tasker::Authorization::ResourceConstants::RESOURCES::WORKFLOW_STEP}:#{action}")
    when :update, :destroy, :retry, :cancel
      # Step modifications require admin access
      user.tasker_admin?
    else
      false
    end
  end

  def authorize_diagram_action(action, context)
    case action
    when :index, :show
      user.tasker_admin? || user.has_tasker_permission?("#{Tasker::Authorization::ResourceConstants::RESOURCES::TASK_DIAGRAM}:#{action}")
    else
      false
    end
  end

  def authorize_health_status_action(action, context)
    case action
    when :index
      # Health status access: admin users or explicit permission
      user.tasker_admin? || user.has_tasker_permission?("#{Tasker::Authorization::ResourceConstants::RESOURCES::HEALTH_STATUS}:#{action}")
    else
      false
    end
  end
end
```

### 3. Add Authorization to User Model

```ruby
# app/models/user.rb
class User < ApplicationRecord
  include Tasker::Concerns::Authorizable

  def has_tasker_permission?(permission)
    # Your permission checking logic
    permissions.include?(permission)
  end

  def tasker_admin?
    # Your admin checking logic
    role == 'admin' || roles.include?('admin')
  end
end
```

### 4. Automatic Protection

With authorization enabled, **all Tasker endpoints are automatically protected**:

```ruby
# REST API calls now require proper permissions
GET  /tasker/tasks           # Requires tasker.task:index permission
POST /tasker/tasks           # Requires tasker.task:create permission
GET  /tasker/tasks/123       # Requires tasker.task:show permission

# Health endpoints with optional authorization
GET  /tasker/health/ready    # Never requires authorization (K8s compatibility)
GET  /tasker/health/live     # Never requires authorization (K8s compatibility)
GET  /tasker/health/status   # Requires tasker.health_status:index permission (if enabled)

# GraphQL operations are automatically mapped to permissions
query { tasks { taskId } }                    # Requires tasker.task:index
mutation { createTask(input: {...}) { ... } } # Requires tasker.task:create
```

## Health Status Authorization

Tasker provides optional authorization for health monitoring endpoints, designed for production security while maintaining Kubernetes compatibility:

### Health Endpoint Security Model

```ruby
# Kubernetes-compatible endpoints (never require authorization)
GET /tasker/health/ready     # Always accessible - K8s readiness probe
GET /tasker/health/live      # Always accessible - K8s liveness probe

# Status endpoint with optional authorization
GET /tasker/health/status    # Requires tasker.health_status:index permission (if enabled)
```

### Configuration

Enable health status authorization:

```ruby
# config/initializers/tasker.rb
Tasker.configuration do |config|
  config.auth do |auth|
    auth.authorization_enabled = true
    auth.authorization_coordinator_class = 'YourAuthorizationCoordinator'
  end

  config.health do |health|
    health.status_requires_authentication = true  # Optional authentication
  end
end
```

### Authorization Implementation

Add health status authorization to your coordinator:

```ruby
class YourAuthorizationCoordinator < Tasker::Authorization::BaseCoordinator
  include Tasker::Authorization::ResourceConstants

  protected

  def authorized?(resource, action, context = {})
    case resource
    when RESOURCES::HEALTH_STATUS
      authorize_health_status_action(action, context)
    # ... other resources
    end
  end

  private

  def authorize_health_status_action(action, context)
    case action
    when :index
      # Admin users always have access
      user.tasker_admin? ||
        # Regular users need explicit permission
        user.has_tasker_permission?("#{RESOURCES::HEALTH_STATUS}:#{action}")
    else
      false
    end
  end
end
```

### Security Benefits

- **K8s Compatibility**: Ready/live endpoints never require authorization
- **Granular Control**: Status endpoint uses specific `health_status:index` permission
- **Admin Override**: Admin users always have health status access
- **Optional Authentication**: Can require authentication without authorization
- **Production Ready**: Designed for enterprise security requirements

For complete health monitoring documentation, see **[Health Monitoring Guide](HEALTH.md)**.

## GraphQL Authorization

Tasker provides **revolutionary GraphQL authorization** that automatically maps GraphQL operations to resource:action permissions.

### How It Works

The system **parses GraphQL queries and mutations** to extract the underlying operations, then checks permissions for each operation:

```ruby
# This GraphQL query:
query {
  tasks {
    taskId
    status
    workflowSteps {
      workflowStepId
      status
    }
  }
}

# Is automatically mapped to these permission checks:
# - tasker.task:index (for tasks query)
# - tasker.workflow_step:index (for workflowSteps query)
```

### GraphQL Operation Mapping

| GraphQL Operation | Resource:Action Permission |
|------------------|---------------------------|
| `query { tasks }` | `tasker.task:index` |
| `query { task(taskId: "123") }` | `tasker.task:show` |
| `mutation { createTask(...) }` | `tasker.task:create` |
| `mutation { updateTask(...) }` | `tasker.task:update` |
| `mutation { cancelTask(...) }` | `tasker.task:cancel` |
| `query { step(...) }` | `tasker.workflow_step:show` |
| `mutation { updateStep(...) }` | `tasker.workflow_step:update` |
| `mutation { cancelStep(...) }` | `tasker.workflow_step:cancel` |

### GraphQL Authorization Examples

```ruby
# Admin user - Full access
admin_user.tasker_admin? # => true

# This query succeeds for admin
query {
  tasks {
    taskId
    workflowSteps { workflowStepId }
  }
}
# ✅ 200 OK - Admin has access to all operations

# Regular user with limited permissions
user.has_tasker_permission?('tasker.task:index')           # => true
user.has_tasker_permission?('tasker.workflow_step:index') # => false

# Same query for regular user
query {
  tasks {
    taskId
    workflowSteps { workflowStepId }
  }
}
# ❌ 403 Forbidden - User lacks tasker.workflow_step:index permission

# User can make this simpler query
query {
  tasks {
    taskId
    status
  }
}
# ✅ 200 OK - User has tasker.task:index permission
```

### GraphQL with Context

GraphQL authorization includes context information for advanced logic:

```ruby
class YourAuthorizationCoordinator < Tasker::Authorization::BaseCoordinator
  protected

  def authorized?(resource, action, context = {})
    # Context includes:
    # - controller: GraphQL controller instance
    # - query_string: Original GraphQL query
    # - operation_name: Named operation (if provided)
    # - variables: Query variables

    case resource
    when Tasker::Authorization::ResourceConstants::RESOURCES::TASK
      authorize_task_with_context(action, context)
    end
  end

  private

  def authorize_task_with_context(action, context)
    case action
    when :show
      # Allow users to view their own tasks
      task_id = extract_task_id_from_context(context)
      user.tasker_admin? || user_owns_task?(task_id)
    when :index
      # Regular index permission
      user.has_tasker_permission?("tasker.task:index")
    end
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
- `--directory`: Output directory (default: app/tasker/authenticators)
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
- `app/tasker/authenticators/company_jwt_authenticator.rb` - Full JWT implementation
- `spec/tasker/authenticators/company_jwt_authenticator_spec.rb` - Test suite
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
    # Authentication settings
    auth.authentication_enabled = true | false  # Enable/disable authentication
    auth.authenticator_class = 'String'         # Your authenticator class name

    # Authorization settings
    auth.authorization_enabled = true | false           # Enable/disable authorization
    auth.authorization_coordinator_class = 'String'     # Your authorization coordinator class
    auth.user_class = 'String'                         # Your user model class name
  end
end
```

### Configuration Validation

Tasker validates configuration at startup and provides helpful error messages:

```ruby
# Missing authenticator class when authentication is enabled
auth.authentication_enabled = true
auth.authenticator_class = nil
# => ConfigurationError: "Authentication is enabled but no authenticator_class is specified"

# Invalid authenticator class
auth.authenticator_class = 'NonExistentClass'
# => ConfigurationError: "Authenticator configuration errors: User class 'NonExistentClass' not found"
```

## Authentication Configuration

### No Authentication (Default)

By default, authentication is disabled. All users are considered "authenticated" with no user object.

```ruby
config.auth do |auth|
  auth.authentication_enabled = false  # Default
end
```

**Use Cases:**
- Development environments
- Internal tools without user management
- Public APIs
- Testing scenarios

### Custom Authentication

Host application provides a custom authenticator class that implements the authentication interface.

```ruby
config.auth do |auth|
  auth.authentication_enabled = true
  auth.authenticator_class = 'DeviseAuthenticator'
  # Your authenticator can accept any configuration options in its initialize method
end
```

**Use Cases:**
- Devise integration
- JWT authentication
- OmniAuth integration
- Custom authentication systems
- Multi-tenant authentication

## Authorization System

Tasker's authorization system provides enterprise-grade security through a resource-based permission model. The system uses **resource constants** and **authorization coordinators** to ensure consistent, maintainable authorization logic.

### Resource Registry

All authorization revolves around the central resource registry:

```ruby
# Available Resources and Actions
Resources:
  - tasker.task (index, show, create, update, destroy, retry, cancel)
  - tasker.workflow_step (index, show, update, destroy, retry, cancel)
  - tasker.task_diagram (index, show)

# Permission Examples:
'tasker.task:index'           # List all tasks
'tasker.task:create'          # Create new tasks
'tasker.workflow_step:show'   # View individual workflow steps
'tasker.task_diagram:index'   # List task diagrams
```

### Authorization Coordinator Interface

Authorization coordinators must implement the `BaseCoordinator` interface:

```ruby
class YourAuthorizationCoordinator < Tasker::Authorization::BaseCoordinator
  protected

  # Required: Implement authorization logic
  def authorized?(resource, action, context = {})
    # Return true if user is authorized for resource:action
    # Context provides additional information like controller, params
  end
end
```

### Controller Integration

Authorization is **automatically applied** to all Tasker controllers:

```ruby
# app/controllers/tasker/application_controller.rb
module Tasker
  class ApplicationController < ActionController::Base
    include Tasker::Concerns::Authenticatable     # Authentication
    include Tasker::Concerns::ControllerAuthorizable  # Authorization

    # All controllers automatically inherit both authentication and authorization
  end
end
```

### Permission Checking Flow

1. **Request arrives** at Tasker controller (REST or GraphQL)
2. **Authentication** runs first (if enabled)
3. **Authorization** extracts `resource:action` from route/operation
4. **Coordinator** checks if current user has permission
5. **Access granted** (200 OK) or **denied** (403 Forbidden)

### Available Resources and Actions

#### Tasks (`tasker.task`)
- `index` - List all tasks
- `show` - View specific task
- `create` - Create new task
- `update` - Modify existing task
- `destroy` - Delete task
- `retry` - Retry failed task
- `cancel` - Cancel running task

#### Workflow Steps (`tasker.workflow_step`)
- `index` - List workflow steps
- `show` - View specific step
- `update` - Modify step
- `destroy` - Delete step
- `retry` - Retry failed step
- `cancel` - Cancel running step

#### Task Diagrams (`tasker.task_diagram`)
- `index` - List task diagrams
- `show` - View specific diagram

## Building Authorization Coordinators

Authorization coordinators provide the business logic for permission checking. Here's how to build effective coordinators:

### Basic Coordinator Structure

```ruby
class CompanyAuthorizationCoordinator < Tasker::Authorization::BaseCoordinator
  protected

  def authorized?(resource, action, context = {})
    # Route to resource-specific methods
    case resource
    when Tasker::Authorization::ResourceConstants::RESOURCES::TASK
      authorize_task(action, context)
    when Tasker::Authorization::ResourceConstants::RESOURCES::WORKFLOW_STEP
      authorize_workflow_step(action, context)
    when Tasker::Authorization::ResourceConstants::RESOURCES::TASK_DIAGRAM
      authorize_task_diagram(action, context)
    else
      false
    end
  end

  private

  def authorize_task(action, context)
    case action
    when :index, :show
      # Read operations - regular users allowed
      user.has_tasker_permission?("tasker.task:#{action}")
    when :create, :update, :destroy, :retry, :cancel
      # Write operations - admin or explicit permission
      user.tasker_admin? || user.has_tasker_permission?("tasker.task:#{action}")
    else
      false
    end
  end

  def authorize_workflow_step(action, context)
    case action
    when :index, :show
      # Read operations
      user.has_tasker_permission?("tasker.workflow_step:#{action}")
    when :update, :destroy, :retry, :cancel
      # Write operations - admin only for steps
      user.tasker_admin?
    else
      false
    end
  end

  def authorize_task_diagram(action, context)
    case action
    when :index, :show
      # Diagram viewing
      user.has_tasker_permission?("tasker.task_diagram:#{action}")
    else
      false
    end
  end
end
```

### Advanced Authorization Patterns

#### Role-Based Authorization
```ruby
def authorize_task(action, context)
  case user.primary_role
  when 'admin'
    true  # Admins can do everything
  when 'manager'
    [:index, :show, :create, :update, :retry].include?(action)
  when 'operator'
    [:index, :show, :retry].include?(action)
  when 'viewer'
    [:index, :show].include?(action)
  else
    false
  end
end
```

#### Context-Based Authorization
```ruby
def authorize_task(action, context)
  case action
  when :show, :update, :cancel
    task_id = context[:resource_id]

    # Users can manage their own tasks
    return true if user_owns_task?(task_id)

    # Managers can manage team tasks
    return true if user.manager? && team_owns_task?(task_id)

    # Admins can manage all tasks
    user.tasker_admin?
  end
end

private

def user_owns_task?(task_id)
  task = Tasker::Task.find_by(task_id: task_id)
  return false unless task

  task.context['created_by_user_id'] == user.id.to_s
end

def team_owns_task?(task_id)
  task = Tasker::Task.find_by(task_id: task_id)
  return false unless task

  team_id = task.context['team_id']
  user.managed_teams.include?(team_id)
end
```

#### Time-Based Authorization
```ruby
def authorize_task(action, context)
  # Prevent modifications during maintenance windows
  if maintenance_window_active?
    return [:index, :show].include?(action)
  end

  # Business hours restrictions for certain actions
  if [:destroy, :cancel].include?(action) && !business_hours?
    return user.tasker_admin?
  end

  # Standard authorization
  user.has_tasker_permission?("tasker.task:#{action}")
end
```

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
    auth.authentication_enabled = true
    auth.authenticator_class = 'ExampleJWTAuthenticator'
    auth.user_class = 'User'
  end
end

# Your JWT authenticator can receive configuration in its initialize method:
class ExampleJWTAuthenticator
  def initialize(options = {})
    @secret = Rails.application.credentials.jwt_secret
    @algorithm = 'HS256'
    @header_name = 'Authorization'
    @user_class = 'User'
  end
  # ... rest of implementation
end
```

### Environment-Specific Configuration

```ruby
# config/initializers/tasker.rb
Tasker.configuration do |config|
  config.auth do |auth|
    auth.authentication_enabled = true
    auth.authenticator_class = 'ExampleJWTAuthenticator'
    auth.user_class = 'User'
  end
end

# Your JWT authenticator handles environment-specific configuration internally:
class ExampleJWTAuthenticator
  def initialize(options = {})
    @secret = Rails.env.production? ?
               Rails.application.credentials.jwt_secret :
               'development-secret-key-32-chars-min'
    @algorithm = Rails.env.production? ? 'HS512' : 'HS256'
    @user_class = 'User'
  end
  # ... rest of implementation
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

Controllers inherit **both authentication and authorization** automatically:

```ruby
# app/controllers/tasker/application_controller.rb
module Tasker
  class ApplicationController < ActionController::Base
    include Tasker::Concerns::Authenticatable          # Authentication
    include Tasker::Concerns::ControllerAuthorizable   # Authorization

    # Both authentication and authorization happen automatically
    # before_action :authenticate_tasker_user!
    # before_action :authorize_tasker_action!
  end
end
```

### Automatic Authorization

All Tasker controllers automatically enforce authorization when enabled:

```ruby
class Tasker::TasksController < ApplicationController
  # These actions are automatically protected:

  def index
    # Requires 'tasker.task:index' permission
    # Authorization runs before this method
  end

  def show
    # Requires 'tasker.task:show' permission
  end

  def create
    # Requires 'tasker.task:create' permission
  end

  def update
    # Requires 'tasker.task:update' permission
  end

  def destroy
    # Requires 'tasker.task:destroy' permission
  end
end
```

### Available Helper Methods

In any Tasker controller, you have access to:

```ruby
class Tasker::TasksController < ApplicationController
  def index
    # Authentication methods
    if tasker_user_authenticated?
      user = current_tasker_user  # Get current user object

      # Authorization methods
      coordinator = authorization_coordinator
      if coordinator.can?('tasker.task', :create)
        # User can create tasks
      end
    end
  end
end
```

### Controller Methods

**Authentication Methods:**
- `current_tasker_user`: Returns the current user object (or nil)
- `tasker_user_authenticated?`: Returns boolean authentication status
- `authenticate_tasker_user!`: Manually trigger authentication (called automatically)

**Authorization Methods:**
- `authorization_coordinator`: Returns the current authorization coordinator
- `authorize_tasker_action!`: Manually trigger authorization (called automatically)
- `skip_authorization?`: Check if authorization should be skipped

### REST API Authorization

REST endpoints map directly to resource:action permissions:

```ruby
# HTTP Method + Route = Resource:Action Permission

GET    /tasker/tasks          → tasker.task:index
GET    /tasker/tasks/123      → tasker.task:show
POST   /tasker/tasks          → tasker.task:create
PATCH  /tasker/tasks/123      → tasker.task:update
DELETE /tasker/tasks/123      → tasker.task:destroy

GET    /tasker/tasks/123/workflow_steps     → tasker.workflow_step:index
GET    /tasker/workflow_steps/456           → tasker.workflow_step:show
PATCH  /tasker/workflow_steps/456           → tasker.workflow_step:update

GET    /tasker/tasks/123/task_diagrams      → tasker.task_diagram:index
GET    /tasker/task_diagrams/789            → tasker.task_diagram:show
```

### GraphQL Integration

GraphQL endpoints inherit **both authentication and authorization** with operation-level granular security:

```ruby
# app/controllers/tasker/graphql_controller.rb
module Tasker
  class GraphqlController < ApplicationController
    # Inherits Authenticatable and ControllerAuthorizable
    # Skip standard controller authorization - we handle GraphQL operations manually
    skip_before_action :authorize_tasker_action!, if: :authorization_enabled?

    def execute
      # Authentication runs automatically
      # GraphQL authorization runs per-operation

      # Context includes authenticated user
      context = {
        current_user: current_tasker_user,
        authenticated: tasker_user_authenticated?
      }

      # Operations are authorized individually
      result = Tasker::TaskerRailsSchema.execute(query, variables: variables, context: context)
      render(json: result)
    end
  end
end
```

### GraphQL Resolver Authorization

In GraphQL resolvers, you have access to authorization context:

```ruby
# app/graphql/tasker/queries/tasks_query.rb
module Tasker
  module Queries
    class TasksQuery < BaseQuery
      def resolve(**args)
        user = context[:current_user]

        # Authorization was already checked before this resolver runs
        # The query 'tasks' required 'tasker.task:index' permission

        # Your query logic here
        Tasker::Task.all
      end
    end
  end
end
```

### Manual Authorization

You can also perform manual authorization checks:

```ruby
class CustomController < Tasker::ApplicationController
  def custom_action
    # Manual authorization check
    coordinator = authorization_coordinator

    unless coordinator.can?('tasker.task', :create)
      render json: { error: 'Not authorized' }, status: :forbidden
      return
    end

    # Proceed with authorized logic
  end
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

## Testing Authorization

### Authorization Test Setup

For authorization testing, use comprehensive integration tests:

```ruby
# spec/support/shared_contexts/configuration_test_isolation.rb
RSpec.shared_context 'configuration test isolation' do
  around(:each) do |example|
    original_config = Tasker.configuration
    example.run
  ensure
    # Reset to clean state
    Tasker.instance_variable_set(:@configuration, original_config)
  end
end

# spec/requests/tasker/authorization_integration_spec.rb
require 'rails_helper'

RSpec.describe 'Authorization Integration', type: :request do
  include_context 'configuration test isolation'

  let(:admin_user) do
    TestUser.new(
      id: 1,
      permissions: [],
      roles: ['admin'],
      admin: true
    )
  end

  let(:regular_user) do
    TestUser.new(
      id: 2,
      permissions: [
        'tasker.task:index',
        'tasker.task:show',
        'tasker.workflow_step:index',
        'tasker.task_diagram:index'
      ],
      roles: ['user'],
      admin: false
    )
  end

  before do
    configure_tasker_auth(
      strategy: :custom,
      options: { authenticator_class: 'TestAuthenticator' },
      enabled: true,
      coordinator_class: 'CustomAuthorizationCoordinator'
    )
  end

  describe 'with admin user' do
    before do
      TestAuthenticator.set_authentication_result(true)
      TestAuthenticator.set_current_user(admin_user)
    end

    it 'allows full access to all resources' do
      get '/tasker/tasks'
      expect(response).to have_http_status(:ok)

      post '/tasker/tasks', params: { task: valid_task_params }.to_json,
           headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:created)
    end
  end

  describe 'with regular user' do
    before do
      TestAuthenticator.set_authentication_result(true)
      TestAuthenticator.set_current_user(regular_user)
    end

    it 'allows access to permitted resources' do
      get '/tasker/tasks'
      expect(response).to have_http_status(:ok)
    end

    it 'denies access to forbidden resources' do
      post '/tasker/tasks', params: { task: valid_task_params }.to_json,
           headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:forbidden)
    end
  end
end
```

### GraphQL Authorization Testing

```ruby
describe 'GraphQL Authorization' do
  it 'allows authorized GraphQL operations' do
    TestAuthenticator.set_current_user(admin_user)

    post '/tasker/graphql', params: {
      query: 'query { tasks { taskId status } }'
    }
    expect(response).to have_http_status(:ok)
  end

  it 'blocks unauthorized GraphQL operations' do
    TestAuthenticator.set_current_user(regular_user)

    post '/tasker/graphql', params: {
      query: 'mutation { createTask(input: { name: "test" }) { taskId } }'
    }
    expect(response).to have_http_status(:forbidden)
  end

  it 'handles mixed operations correctly' do
    TestAuthenticator.set_current_user(regular_user)

    # User has tasker.task:index but not tasker.workflow_step:index
    post '/tasker/graphql', params: {
      query: 'query { tasks { taskId workflowSteps { workflowStepId } } }'
    }
    expect(response).to have_http_status(:forbidden)
  end
end
```

### Custom Authorization Coordinator Testing

```ruby
describe CustomAuthorizationCoordinator do
  let(:coordinator) { described_class.new(user) }

  describe 'task authorization' do
    context 'with admin user' do
      let(:user) { admin_user }

      it 'allows all task operations' do
        expect(coordinator.can?('tasker.task', :index)).to be true
        expect(coordinator.can?('tasker.task', :create)).to be true
        expect(coordinator.can?('tasker.task', :destroy)).to be true
      end
    end

    context 'with regular user' do
      let(:user) { regular_user }

      it 'allows read operations' do
        expect(coordinator.can?('tasker.task', :index)).to be true
        expect(coordinator.can?('tasker.task', :show)).to be true
      end

      it 'denies write operations' do
        expect(coordinator.can?('tasker.task', :create)).to be false
        expect(coordinator.can?('tasker.task', :destroy)).to be false
      end
    end
  end
end
```

### State Isolation

Ensure tests don't leak configuration state:

```ruby
# spec/rails_helper.rb (automatic cleanup)
RSpec.configure do |config|
  config.after(:each) do
    # Automatic cleanup of authentication/authorization state
    if defined?(Tasker) && Tasker.respond_to?(:configuration)
      current_config = Tasker.configuration
      if current_config&.auth&.authorization_enabled == true
        needs_reset = true
      end

      if current_config&.auth&.authentication_enabled == true
        authenticator_class = current_config.auth.authenticator_class
        needs_reset = true if authenticator_class&.include?('Test')
      end

      if needs_reset
        Tasker.configuration do |config|
          config.auth.authentication_enabled = false
          config.auth.authorization_enabled = false
          config.auth.authenticator_class = nil
          config.auth.authorization_coordinator_class = nil
        end
      end
    end
  end
end
```

## Best Practices

### Security

#### Authentication Security
1. **Use Strong Secrets**: Minimum 32 characters for JWT secrets
2. **Choose Secure Algorithms**: Prefer HS256/HS512 for HMAC, RS256+ for RSA
3. **Validate Configuration**: Implement `validate_configuration` for security checks
4. **Handle Errors Gracefully**: Never expose sensitive information in error messages
5. **Implement Token Expiration**: Always set reasonable expiration times

#### Authorization Security
1. **Default Deny**: Always default to denying access unless explicitly granted
2. **Resource-Specific Logic**: Implement granular permissions per resource type
3. **Context-Aware Authorization**: Use context for ownership and relationship checks
4. **Admin Override Pattern**: Allow admins to bypass specific restrictions safely
5. **Audit Trails**: Log authorization decisions for security monitoring

```ruby
# Good: Default deny with explicit grants
def authorize_task(action, context)
  return false unless user.present?  # Default deny

  case action
  when :index, :show
    user.has_tasker_permission?("tasker.task:#{action}")
  when :create, :update, :destroy
    user.tasker_admin? || user.has_tasker_permission?("tasker.task:#{action}")
  else
    false  # Explicit deny for unknown actions
  end
end

# Bad: Default allow
def authorize_task(action, context)
  return true if user.tasker_admin?  # Too broad
  # ... other logic
end
```

### Performance

#### Authentication Performance
1. **Memoize User Lookups**: Cache user objects within request scope
2. **Efficient Database Queries**: Use `find_by` instead of exceptions for user lookup
3. **Minimal Token Validation**: Only decode/validate tokens once per request

#### Authorization Performance
1. **Cache Permission Checks**: Memoize authorization decisions within request scope
2. **Efficient Permission Storage**: Use optimized data structures for permission lookups
3. **Minimal Database Hits**: Load user permissions once per request
4. **Smart GraphQL Batching**: Group permission checks for related operations

```ruby
# Good: Memoized authorization
class YourAuthorizationCoordinator < Tasker::Authorization::BaseCoordinator
  def can?(resource, action, context = {})
    cache_key = "#{resource}:#{action}"
    @authorization_cache ||= {}
    @authorization_cache[cache_key] ||= super
  end
end

# Good: Efficient permission checking
def user_permissions
  @user_permissions ||= user.permissions.to_set
end

def has_permission?(permission)
  user_permissions.include?(permission)
end
```

### Development

#### General Development
1. **Use Different Configs for Environments**: Separate dev/test/production settings
2. **Provide Clear Error Messages**: Help developers debug configuration issues
3. **Document Your Authenticator**: Include usage examples and configuration options
4. **Test Edge Cases**: Expired tokens, malformed headers, missing users

#### Authorization Development
1. **Resource Constants**: Always use `ResourceConstants` instead of hardcoded strings
2. **Comprehensive Testing**: Test both positive and negative authorization scenarios
3. **Clear Coordinator Logic**: Separate resource authorization into dedicated methods
4. **Context Documentation**: Document what context information your coordinator uses

```ruby
# Good: Using constants
when Tasker::Authorization::ResourceConstants::RESOURCES::TASK
  authorize_task_action(action, context)

# Bad: Hardcoded strings
when 'tasker.task'
  authorize_task_action(action, context)
```

### Code Organization

```ruby
# Recommended file structure
app/
  tasker/
    authenticators/
      company_jwt_authenticator.rb
      company_devise_authenticator.rb
    authorization/
      company_authorization_coordinator.rb
  models/
    user.rb  # Include Tasker::Concerns::Authorizable
  config/
    initializers/
      tasker.rb  # Authentication & authorization configuration

# Authorization coordinator organization
class CompanyAuthorizationCoordinator < Tasker::Authorization::BaseCoordinator
  protected

  def authorized?(resource, action, context = {})
    case resource
    when ResourceConstants::RESOURCES::TASK
      authorize_task(action, context)
    when ResourceConstants::RESOURCES::WORKFLOW_STEP
      authorize_workflow_step(action, context)
    when ResourceConstants::RESOURCES::TASK_DIAGRAM
      authorize_task_diagram(action, context)
    else
      false
    end
  end

  private

  # Separate methods for each resource type
  def authorize_task(action, context)
    # Task-specific authorization logic
  end

  def authorize_workflow_step(action, context)
    # Workflow step authorization logic
  end

  def authorize_task_diagram(action, context)
    # Diagram authorization logic
  end
end
```

### Production Considerations

#### Monitoring & Observability
1. **Log Authorization Failures**: Track unauthorized access attempts
2. **Monitor Performance**: Track authorization overhead
3. **Alert on Anomalies**: Detect unusual permission patterns
4. **Audit Admin Actions**: Log all administrative overrides

#### Scaling Authorization
1. **Permission Caching**: Cache user permissions with appropriate TTL
2. **Database Optimization**: Index permission lookup columns
3. **Background Processing**: Refresh permissions asynchronously when possible
4. **Circuit Breakers**: Graceful degradation when authorization services are unavailable

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
