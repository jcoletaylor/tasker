# Step Handler Best Practices Guide

*A comprehensive guide to writing robust, idempotent, and maintainable step handlers in Tasker workflows*

## Table of Contents

1. [Overview](#overview)
2. [The Four-Phase Pattern](#the-four-phase-pattern)
3. [Implementation Patterns](#implementation-patterns)
4. [Error Handling & Retry Safety](#error-handling--retry-safety)
5. [Idempotency Principles](#idempotency-principles)
6. [Base Class Selection](#base-class-selection)
7. [Testing Patterns](#testing-patterns)
8. [Examples from the Blog Series](#examples-from-the-blog-series)

## Overview

Step handlers are the core business logic units in Tasker workflows. While the system only requires a `process` method, following established patterns ensures:

- **Idempotency**: Operations can be safely retried without side effects
- **Retry Safety**: Clear separation between retryable and permanent failures
- **Maintainability**: Consistent structure across your codebase
- **Testability**: Predictable interfaces for comprehensive testing

### Core Philosophy

> **The business logic call must be safe to retry, or intentionally not retryable, in a way that ensures idempotency.**

Too many distributed systems enter invalid states due to poorly handled secondary actions. By following these patterns, we prevent such issues.

## The Four-Phase Pattern

Every step handler should follow this proven four-phase pattern:

### Phase 1: Extract and Validate Inputs
- Extract all required data from task context and previous step results
- Validate inputs early with `PermanentError` for missing/invalid data
- Normalize data formats (e.g., symbolize keys)
- Fail fast with clear error messages

### Phase 2: Execute Business Logic
- Perform the core operation (computation, API call, data transformation)
- Handle service-specific errors appropriately
- Return raw results for phase 3 validation

### Phase 3: Validate Business Logic Results
- Ensure the operation completed successfully
- Check for business-level failures (e.g., payment declined)
- Classify errors correctly (`PermanentError` vs `RetryableError`)

### Phase 4: Process Results (Optional)
- Override `process_results` when needed
- Format and store step results safely
- Handle result processing errors as `PermanentError` (don't retry business logic)

## Implementation Patterns

### Basic Step Handler Structure

```ruby
module YourNamespace
  module StepHandlers
    class YourStepHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        # Phase 1: Extract and validate inputs
        inputs = extract_and_validate_inputs(task, sequence, step)
        
        Rails.logger.info "Processing #{step.name}: #{inputs.inspect}"
        
        # Phase 2: Execute business logic
        begin
          result = execute_business_logic(inputs)
          
          # Phase 3: Validate business logic results
          ensure_operation_successful!(result)
          
          # Return result for process_results
          result
        rescue YourService::ServiceError => e
          # Handle service-specific exceptions with proper classification
          handle_service_error(e)
        end
      end
      
      # Phase 4: Process results (optional override)
      def process_results(step, service_response, _initial_results)
        # Safe result processing - format and store results
        step.results = format_results(service_response)
      rescue StandardError => e
        # Result processing failures are permanent - don't retry business logic
        raise Tasker::PermanentError,
              "Failed to process results: #{e.message}"
      end
      
      private
      
      def extract_and_validate_inputs(task, sequence, step)
        # Implementation details...
      end
      
      def execute_business_logic(inputs)
        # Implementation details...
      end
      
      def ensure_operation_successful!(result)
        # Implementation details...
      end
      
      def handle_service_error(error)
        # Implementation details...
      end
      
      def format_results(response)
        # Implementation details...
      end
    end
  end
end
```

### Input Extraction and Validation Pattern

```ruby
def extract_and_validate_inputs(task, sequence, step)
  # Normalize all hash keys to symbols for consistent access
  context = task.context.deep_symbolize_keys
  
  # Extract required fields with clear validation
  email = context[:user_info]&.dig(:email)
  unless email
    raise Tasker::PermanentError.new(
      'Email is required but was not provided',
      error_code: 'MISSING_EMAIL'
    )
  end
  
  # Get results from previous steps
  validation_step = sequence.find_step_by_name('validate_user')
  validation_results = validation_step&.results&.deep_symbolize_keys
  
  unless validation_results&.dig(:user_validated)
    raise Tasker::PermanentError,
          'User validation must complete before proceeding'
  end
  
  # Return structured, validated inputs
  {
    email: email,
    user_id: validation_results[:user_id],
    preferences: context[:preferences] || {},
    force_update: context[:force_update] || false
  }
end
```

### API Configuration Pattern

For `Tasker::StepHandler::Api` handlers, configure the base URL and connection settings in the YAML configuration, not in the handler code:

```yaml
# In your task handler YAML file
step_templates:
  - name: call_external_api
    handler_class: "YourNamespace::StepHandlers::ExternalApiHandler"
    default_retry_limit: 3                        # Step template level
    default_retryable: true                       # Step template level
    handler_config:                               # API config level
      url: "https://api.example.com"
      retry_delay: 2.0
      enable_exponential_backoff: true
      jitter_factor: 0.1
      headers:
        "Authorization": "Bearer ${API_TOKEN}"
```

The framework automatically passes this configuration to the handler:

```ruby
# In your test setup
let(:handler_config) { Tasker::StepHandler::Api::Config.new(url: 'https://api.example.com') }
let(:handler) { handler_class.new(config: handler_config) }
```

### Business Logic Execution Pattern

```ruby
def execute_business_logic(inputs)
  start_time = Time.current
  
  # Log operation start
  Rails.logger.info "Starting operation: #{inputs[:operation_type]}"
  
  # Execute the core business logic
  result = YourService.perform_operation(
    user_id: inputs[:user_id],
    operation_data: inputs[:operation_data],
    timeout: 30
  )
  
  # Log operation completion
  duration = Time.current - start_time
  Rails.logger.info "Operation completed in #{duration}s"
  
  result
rescue YourService::NetworkError => e
  # Network errors are typically retryable
  raise Tasker::RetryableError, "Service network error: #{e.message}"
rescue YourService::AuthenticationError => e
  # Authentication errors are permanent
  raise Tasker::PermanentError.new(
    "Service authentication failed: #{e.message}",
    error_code: 'AUTHENTICATION_FAILED'
  )
rescue YourService::ValidationError => e
  # Business validation errors are permanent
  raise Tasker::PermanentError.new(
    "Invalid operation data: #{e.message}",
    error_code: 'INVALID_DATA'
  )
end
```

### Result Validation Pattern

```ruby
def ensure_operation_successful!(result)
  # Check for business-level success indicators
  case result[:status]
  when 'success', 'completed'
    # Operation succeeded
    unless result[:operation_id]
      raise Tasker::PermanentError,
            'Operation succeeded but no operation ID returned'
    end
  when 'insufficient_funds', 'limit_exceeded'
    # Business rule violations - permanent errors
    raise Tasker::PermanentError.new(
      "Operation rejected: #{result[:reason]}",
      error_code: 'BUSINESS_RULE_VIOLATION'
    )
  when 'rate_limited'
    # Temporary service limitations - retryable
    raise Tasker::RetryableError.new(
      'Service rate limited',
      retry_after: result[:retry_after] || 60
    )
  when 'service_unavailable'
    # Temporary service issues - retryable
    raise Tasker::RetryableError, 'Service temporarily unavailable'
  else
    # Unknown status - log and treat as retryable for safety
    Rails.logger.error "Unknown operation status: #{result[:status]}"
    raise Tasker::RetryableError, "Unknown operation status: #{result[:status]}"
  end
end
```

## Error Handling & Retry Safety

### Error Classification Principles

**Use `PermanentError` for:**
- Missing or invalid input data
- Authentication/authorization failures
- Business rule violations (insufficient funds, invalid state)
- Structural errors (missing required fields in responses)

**Use `RetryableError` for:**
- Network timeouts and connection errors
- Service unavailable (5xx status codes)
- Rate limiting (429 status codes)
- Temporary resource constraints

### Error Classification Examples

```ruby
def handle_service_error(error)
  case error.error_code
  when 'NETWORK_ERROR', 'TIMEOUT', 'CONNECTION_REFUSED'
    # Infrastructure issues - retryable
    raise Tasker::RetryableError, "Service network error: #{error.message}"
  when 'INVALID_REQUEST', 'MISSING_FIELD', 'MALFORMED_DATA'
    # Request structure issues - permanent
    raise Tasker::PermanentError.new(
      "Invalid request: #{error.message}",
      error_code: error.error_code
    )
  when 'UNAUTHORIZED', 'FORBIDDEN', 'AUTHENTICATION_FAILED'
    # Security issues - permanent
    raise Tasker::PermanentError.new(
      "Authorization failed: #{error.message}",
      error_code: error.error_code
    )
  when 'RATE_LIMITED'
    # Temporary throttling - retryable with backoff
    raise Tasker::RetryableError.new(
      'Service rate limited',
      retry_after: error.retry_after || 30
    )
  else
    # Unknown errors - treat as retryable for safety
    Rails.logger.error "Unknown service error: #{error.error_code}"
    raise Tasker::RetryableError, "Service error: #{error.message}"
  end
end
```

## Idempotency Principles

### Key Concepts

1. **Idempotent Operations**: Can be performed multiple times with the same result
2. **Side Effect Isolation**: Separate side effects from core business logic
3. **State Verification**: Check current state before making changes
4. **Compensation Patterns**: Handle partial failures gracefully

### Idempotency Implementation Patterns

```ruby
def execute_business_logic(inputs)
  user_id = inputs[:user_id]
  
  # Check current state before making changes
  existing_user = UserService.get_user(user_id)
  
  if existing_user && user_matches?(existing_user, inputs)
    # Idempotent success - user already exists with correct data
    Rails.logger.info "User already exists with correct data: #{user_id}"
    return {
      user_id: existing_user[:id],
      status: 'already_exists',
      created_at: existing_user[:created_at]
    }
  elsif existing_user
    # Conflict - user exists but with different data
    raise Tasker::PermanentError.new(
      "User #{user_id} exists with conflicting data",
      error_code: 'USER_CONFLICT'
    )
  end
  
  # Safe to create new user
  result = UserService.create_user(inputs)
  
  # Verify creation succeeded
  unless result[:user_id]
    raise Tasker::PermanentError, 'User creation failed - no user ID returned'
  end
  
  result
end

private

def user_matches?(existing_user, new_user_data)
  # Define what constitutes "matching" for idempotency
  existing_user[:email] == new_user_data[:email] &&
    existing_user[:name] == new_user_data[:name] &&
    existing_user[:plan] == new_user_data[:plan]
end
```

## Base Class Selection

Choose the appropriate base class based on your step handler's purpose:

### `Tasker::StepHandler::Base`
- **Use for**: Computational tasks, data transformations, internal operations
- **Examples**: Data validation, calculations, internal service calls
- **Pattern**: Direct business logic execution

```ruby
class CalculateShippingHandler < Tasker::StepHandler::Base
  def process(task, sequence, step)
    # Direct computation
    shipping_cost = calculate_shipping(task.context)
    { shipping_cost: shipping_cost }
  end
end
```

### `Tasker::StepHandler::Api`
- **Use for**: HTTP API calls, external service integration
- **Examples**: Payment processing, user creation, external notifications
- **Pattern**: HTTP client with automatic retry and circuit breaker support
- **Configuration**: URL and connection settings via YAML `handler_config`

```ruby
class CreateUserHandler < Tasker::StepHandler::Api
  def process(task, sequence, step)
    # HTTP API call with built-in retry logic
    user_data = extract_user_data(task.context)
    response = connection.post('/users', user_data)
    
    case response.status
    when 201
      response
    when 409
      handle_conflict(response)
    else
      raise Tasker::RetryableError, "Unexpected status: #{response.status}"
    end
  end
end
```

**YAML Configuration:**
```yaml
step_templates:
  - name: create_user_account
    handler_class: "CreateUserHandler"
    default_retry_limit: 3                    # Step template level
    default_retryable: true                   # Step template level
    handler_config:                           # API config level
      url: "https://user-service.example.com"
      retry_delay: 1.0
      enable_exponential_backoff: true
      headers:
        "Content-Type": "application/json"
```

## Testing Patterns

### Comprehensive Test Structure

```ruby
RSpec.describe 'YourNamespace::StepHandlers::YourHandler', type: :blog_example do
  let(:handler_class) { YourNamespace::StepHandlers::YourHandler }
  let(:handler) { handler_class.new }
  
  let(:mock_task) { double('Task', context: valid_context) }
  let(:mock_sequence) { double('Sequence') }
  let(:mock_step) { double('Step') }
  
  describe '#process' do
    context 'with valid inputs' do
      it 'processes successfully' do
        result = handler.process(mock_task, mock_sequence, mock_step)
        expect(result).to include(expected_fields)
      end
    end
    
    context 'with missing required inputs' do
      let(:invalid_context) { valid_context.except(:required_field) }
      let(:mock_task) { double('Task', context: invalid_context) }
      
      it 'raises permanent error for missing inputs' do
        expect { handler.process(mock_task, mock_sequence, mock_step) }
          .to raise_error(Tasker::PermanentError, /required_field/)
      end
    end
    
    context 'with service errors' do
      before do
        allow(YourService).to receive(:call).and_raise(service_error)
      end
      
      context 'network error' do
        let(:service_error) { YourService::NetworkError.new('Connection failed') }
        
        it 'raises retryable error' do
          expect { handler.process(mock_task, mock_sequence, mock_step) }
            .to raise_error(Tasker::RetryableError, /network error/)
        end
      end
      
      context 'authentication error' do
        let(:service_error) { YourService::AuthError.new('Invalid token') }
        
        it 'raises permanent error' do
          expect { handler.process(mock_task, mock_sequence, mock_step) }
            .to raise_error(Tasker::PermanentError, /authentication/)
        end
      end
    end
  end
  
  describe '#process_results' do
    let(:service_response) { { status: 'success', id: '123' } }
    
    it 'formats results correctly' do
      allow(mock_step).to receive(:results=)
      
      handler.process_results(mock_step, service_response, {})
      
      expect(mock_step).to have_received(:results=).with(
        hash_including(
          operation_successful: true,
          operation_id: '123'
        )
      )
    end
  end
end
```

## Examples from the Blog Series

### Post 01: E-commerce Reliability Pattern
**File**: `spec/blog/fixtures/post_01_ecommerce_reliability/step_handlers/process_payment_handler.rb`

- **Phase 1**: Validates payment method, token, and cart total
- **Phase 2**: Calls MockPaymentService with retry logic
- **Phase 3**: Checks payment status and handles declines vs temporary failures
- **Phase 4**: Formats payment results with transaction details

**Key Learning**: Payment declines are permanent errors, but rate limiting is retryable.

### Post 02: Data Pipeline Resilience Pattern
**File**: `spec/blog/fixtures/post_02_data_pipeline_resilience/step_handlers/extract_orders_handler.rb`

- **Phase 1**: Validates date range parameters
- **Phase 2**: Extracts data from MockDataWarehouseService
- **Phase 3**: Verifies extraction completed successfully
- **Phase 4**: Stores extraction metadata and metrics

**Key Learning**: Data extraction timeouts are retryable, but query errors are permanent.

### Post 03: Microservices Coordination Pattern
**File**: `spec/blog/fixtures/post_03_microservices_coordination/step_handlers/create_user_account_handler.rb`

- **Phase 1**: Validates user data requirements
- **Phase 2**: HTTP API call to user service with circuit breaker
- **Phase 3**: Handles HTTP status codes and idempotency checks
- **Phase 4**: Processes different response scenarios (created vs already exists)

**Key Learning**: User conflicts require idempotency checks to determine if it's an error or success.

### Post 04: Team Scaling Pattern
**File**: `spec/blog/fixtures/post_04_team_scaling/step_handlers/customer_success/execute_refund_workflow_handler.rb`

- **Phase 1**: Validates approval workflow and maps team-specific data
- **Phase 2**: Cross-namespace HTTP API call to payments team
- **Phase 3**: Handles task creation status from remote team
- **Phase 4**: Formats delegation results with correlation tracking

**Key Learning**: Cross-team coordination requires careful data mapping and correlation tracking.

## Common Anti-Patterns to Avoid

### ❌ Don't Do This

```ruby
# Anti-pattern: Side effects in process method
def process(task, sequence, step)
  result = SomeService.call(task.context)
  
  # ❌ BAD: Side effects that can't be retried safely
  NotificationService.send_email(result[:email])
  AuditLog.create(action: 'processed', result: result)
  
  result
end
```

### ✅ Do This Instead

```ruby
# Pattern: Isolate side effects in process_results
def process(task, sequence, step)
  # Only core business logic in process
  result = SomeService.call(task.context)
  ensure_operation_successful!(result)
  result
end

def process_results(step, service_response, _initial_results)
  # Side effects in process_results (not retried with business logic)
  step.results = format_results(service_response)
  
  # Use event system for side effects
  publish_event('operation_completed', {
    operation_id: service_response[:id],
    user_id: service_response[:user_id]
  })
rescue StandardError => e
  raise Tasker::PermanentError, "Failed to process results: #{e.message}"
end
```

## Summary

Following these patterns ensures:

1. **Robust Error Handling**: Clear classification of permanent vs retryable errors
2. **Idempotent Operations**: Safe retry behavior without side effects
3. **Maintainable Code**: Consistent structure across all step handlers
4. **Comprehensive Testing**: Predictable interfaces for thorough test coverage
5. **Production Readiness**: Battle-tested patterns from real-world usage

Remember: The goal is not rigid adherence to rules, but building reliable, maintainable distributed systems that handle failures gracefully.

---

*This guide is maintained as a living document based on patterns proven in the Tasker blog examples and production usage.*