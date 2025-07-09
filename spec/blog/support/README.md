# Step Handler Development Guide

This directory contains comprehensive resources for writing robust, idempotent, and maintainable step handlers in Tasker workflows.

## Quick Start

**New to step handlers?** Start with the [checklist](STEP_HANDLER_CHECKLIST.md) for a quick overview.

**Need examples?** Check out the [executable examples](step_handler_examples.rb) and [blog fixtures](../fixtures/).

**Want the full story?** Read the [complete best practices guide](STEP_HANDLER_BEST_PRACTICES.md).

## Files in This Directory

### Core Documentation
- **[STEP_HANDLER_BEST_PRACTICES.md](STEP_HANDLER_BEST_PRACTICES.md)** - Complete guide covering principles, patterns, and examples
- **[STEP_HANDLER_CHECKLIST.md](STEP_HANDLER_CHECKLIST.md)** - Quick reference checklist for development
- **[step_handler_examples.rb](step_handler_examples.rb)** - Executable code examples demonstrating patterns

### Supporting Infrastructure
- **[blog_spec_helper.rb](blog_spec_helper.rb)** - Test infrastructure for blog examples
- **[mock_services/](mock_services/)** - Mock services for testing external dependencies
- **[shared_examples/](shared_examples/)** - Reusable test patterns
- **[test_data/](test_data/)** - Sample data for consistent testing

## The Four-Phase Pattern

All step handlers should follow this proven pattern:

1. **Extract & Validate Inputs** - Get and validate all required data
2. **Execute Business Logic** - Perform the core operation
3. **Validate Results** - Ensure the operation succeeded
4. **Process Results** *(optional)* - Format and store step results

## Quick Examples

### Basic Computational Handler
```ruby
class CalculateShippingHandler < Tasker::StepHandler::Base
  def process(task, sequence, step)
    inputs = extract_and_validate_inputs(task, sequence, step)
    result = calculate_shipping_cost(inputs)
    ensure_calculation_valid!(result)
    result
  end
end
```

### API Integration Handler  
```ruby
class CreateUserHandler < Tasker::StepHandler::Api
  def process(task, sequence, step)
    inputs = extract_and_validate_inputs(task, sequence, step)
    response = connection.post('/users', inputs)
    handle_api_response(response)
  end
  # Note: Base URL is configured in YAML handler_config, not in code
end
```

**YAML Configuration:**
```yaml
step_templates:
  - name: create_user
    handler_class: "CreateUserHandler"
    default_retry_limit: 3           # Step template level
    default_retryable: true          # Step template level
    handler_config:                  # API config level
      url: "https://user-service.example.com"
      retry_delay: 1.0
      enable_exponential_backoff: true
```

### Cross-Team Coordination Handler
```ruby
class DelegateToPaymentsHandler < Tasker::StepHandler::Api
  def process(task, sequence, step)
    inputs = extract_and_validate_inputs(task, sequence, step)
    response = connection.post('/tasker/tasks', inputs)
    ensure_delegation_successful!(response)
    response
  end
end
```

## Error Classification

**Use `PermanentError` for:**
- Invalid or missing input data
- Authentication/authorization failures
- Business rule violations
- Configuration errors

**Use `RetryableError` for:**
- Network timeouts and connection issues
- Service unavailable (5xx status codes)
- Rate limiting (429 status code)
- Temporary resource constraints

## Real-World Examples

The [blog fixtures](../fixtures/) contain production-ready examples:

- **[Post 01](../fixtures/post_01_ecommerce_reliability/)** - E-commerce payment processing
- **[Post 02](../fixtures/post_02_data_pipeline_resilience/)** - Data extraction and transformation  
- **[Post 03](../fixtures/post_03_microservices_coordination/)** - HTTP API integration
- **[Post 04](../fixtures/post_04_team_scaling/)** - Cross-namespace workflow coordination

Each example demonstrates:
- Input validation patterns
- Error handling strategies
- Idempotency implementation
- Result processing techniques

## Testing Your Step Handlers

Use the test infrastructure provided:

```ruby
require_relative '../support/blog_spec_helper'

RSpec.describe 'YourNamespace::StepHandlers::YourHandler', type: :blog_example do
  let(:handler) { described_class.new }
  
  it 'processes valid inputs successfully' do
    result = handler.process(mock_task, mock_sequence, mock_step)
    expect(result).to include(expected_fields)
  end
  
  it 'raises permanent error for invalid inputs' do
    expect { handler.process(invalid_task, mock_sequence, mock_step) }
      .to raise_error(Tasker::PermanentError)
  end
end
```

## Key Principles

### Idempotency
Operations must be safely retryable without side effects:
- Check current state before making changes
- Handle "already exists" scenarios gracefully  
- Separate side effects from core business logic

### Retry Safety
Clear error classification enables intelligent retry behavior:
- Business logic failures should not be retried
- Infrastructure failures should trigger retries
- Include helpful context in error messages

### Separation of Concerns
Keep the `process` method focused on business logic:
- Input validation happens first
- Side effects belong in `process_results` or event subscribers
- Error handling is explicit and well-classified

## Getting Help

- **Documentation issues**: Check the [troubleshooting section](STEP_HANDLER_BEST_PRACTICES.md#common-anti-patterns-to-avoid)
- **Code examples**: Review the [blog fixtures](../fixtures/) for similar patterns
- **Testing questions**: Use the [mock services](mock_services/) for external dependencies

---

*This guide is maintained as a living document based on patterns proven in production usage.*