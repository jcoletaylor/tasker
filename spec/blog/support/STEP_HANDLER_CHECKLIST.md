# Step Handler Development Checklist

*Quick reference for implementing step handlers following Tasker best practices*

## Pre-Implementation

- [ ] **Choose appropriate base class**
  - `Tasker::StepHandler::Base` for computational tasks
  - `Tasker::StepHandler::Api` for HTTP API calls

- [ ] **Define the operation's scope**
  - What is the single responsibility of this step?
  - What inputs does it need?
  - What outputs should it produce?

## Phase 1: Input Extraction & Validation

- [ ] **Extract all required inputs**
  - Task context data
  - Previous step results
  - Configuration parameters

- [ ] **Normalize data formats**
  - Use `deep_symbolize_keys` for hash access
  - Trim and standardize string inputs
  - Convert to appropriate data types

- [ ] **Validate inputs early**
  - Check for required fields
  - Validate data formats and constraints
  - Use `PermanentError` for validation failures
  - Include helpful error messages and error codes

- [ ] **Handle missing dependencies**
  - Check required previous steps completed
  - Validate step results contain expected data
  - Fail fast with clear error messages

## Phase 2: Business Logic Execution

- [ ] **Implement core operation**
  - Keep business logic focused and simple
  - Log operation start/completion
  - Handle service-specific exceptions

- [ ] **Error handling during execution**
  - Catch service-specific exceptions
  - Classify errors correctly:
    - `PermanentError`: Invalid data, auth failures, business rule violations
    - `RetryableError`: Network issues, rate limits, service unavailable
  - Include retry hints (`retry_after`) when appropriate

- [ ] **Return raw results**
  - Don't format results in the process method
  - Return service responses for Phase 4 processing
  - Let process_results handle formatting

## Phase 3: Business Logic Validation

- [ ] **Validate operation success**
  - Check service response status/error codes
  - Verify expected data is present
  - Handle business-level failures appropriately

- [ ] **Handle idempotency**
  - Check if operation already completed
  - Compare existing state with desired state
  - Return success for idempotent operations

- [ ] **Log operation results**
  - Log successful completions with key identifiers
  - Log business-level failures for debugging
  - Include correlation IDs for tracing

## Phase 4: Result Processing (if needed)

- [ ] **Override process_results when needed**
  - Format and structure step results
  - Extract key data from service responses
  - Store relevant metadata

- [ ] **Handle result processing errors**
  - Wrap in `PermanentError` (don't retry business logic)
  - Include descriptive error messages
  - Log failures for debugging

- [ ] **Use events for side effects**
  - Publish events instead of direct side effects
  - Include correlation data in events
  - Let event subscribers handle notifications/logging

## Error Classification Guidelines

### Use `PermanentError` for:
- [ ] Missing or invalid input data
- [ ] Authentication/authorization failures  
- [ ] Business rule violations (insufficient funds, invalid state)
- [ ] Structural errors (missing required response fields)
- [ ] Configuration errors (invalid URLs, missing settings)

### Use `RetryableError` for:
- [ ] Network timeouts and connection errors
- [ ] Service unavailable (5xx HTTP status codes)
- [ ] Rate limiting (429 HTTP status code)
- [ ] Temporary resource constraints
- [ ] Unknown errors (when in doubt, make it retryable)

## Testing Requirements

- [ ] **Test happy path**
  - Valid inputs produce expected results
  - Verify result format and content

- [ ] **Test input validation**
  - Missing required fields raise `PermanentError`
  - Invalid data formats raise `PermanentError`
  - Error messages are descriptive

- [ ] **Test error scenarios**
  - Service errors are classified correctly
  - Network errors raise `RetryableError`
  - Business errors raise `PermanentError`

- [ ] **Test idempotency**
  - Operations can be safely retried
  - Existing state is checked before changes
  - Conflicting data raises appropriate errors

- [ ] **Test process_results (if implemented)**
  - Results are formatted correctly
  - Result processing errors are handled
  - Step results include expected fields

## Code Quality Checks

- [ ] **Follow naming conventions**
  - Class names end with `Handler`
  - Method names are descriptive
  - Variable names are clear

- [ ] **Documentation**
  - Class has docstring explaining purpose
  - Complex logic has inline comments
  - Error conditions are documented

- [ ] **Logging**
  - Operation start/completion are logged
  - Include relevant identifiers (user_id, order_id, etc.)
  - Use appropriate log levels

- [ ] **Performance considerations**
  - Avoid N+1 queries in loops
  - Use timeouts for external calls
  - Consider memory usage for large datasets

## Security Checks

- [ ] **Input sanitization**
  - Validate all user inputs
  - Escape data for external systems
  - Avoid SQL injection, XSS risks

- [ ] **Secrets handling**
  - Use environment variables for secrets
  - Don't log sensitive data
  - Use secure HTTP headers

- [ ] **Authorization**
  - Verify user permissions for operations
  - Validate cross-team access rights
  - Check resource ownership

## Deployment Readiness

- [ ] **Configuration**
  - All environment variables documented
  - Default values for optional settings
  - Configuration validation

- [ ] **Monitoring**
  - Key metrics are exposed
  - Error conditions trigger alerts
  - Performance metrics are tracked

- [ ] **Rollback plan**
  - Operations are idempotent
  - Partial failures can be recovered
  - Data migration plan if needed

## Configuration Reference

### Step Template Level (in YAML)
These properties are defined at the step template level:
```yaml
step_templates:
  - name: your_step_name
    handler_class: "YourNamespace::StepHandlers::YourHandler"
    default_retry_limit: 3        # Step template level ✓
    default_retryable: true       # Step template level ✓
    depends_on_step: "other_step" # Step template level ✓
    handler_config:               # This whole object goes to handler ✓
      # API handler config properties go here...
```

### API Handler Config Level (inside handler_config)
For `Tasker::StepHandler::Api`, these properties go inside `handler_config`:
```yaml
handler_config:
  url: "https://api.example.com"           # API config level ✓
  retry_delay: 1.0                         # API config level ✓
  enable_exponential_backoff: true         # API config level ✓
  jitter_factor: 0.1                       # API config level ✓
  headers:                                 # API config level ✓
    "Authorization": "Bearer ${API_TOKEN}"
  params:                                  # API config level ✓
    api_version: "v1"
```

## Example Implementation Template

```ruby
module YourNamespace
  module StepHandlers
    class YourHandler < Tasker::StepHandler::Base # or ::Api
      def process(task, sequence, step)
        # Phase 1: Extract and validate inputs
        inputs = extract_and_validate_inputs(task, sequence, step)
        
        # Phase 2: Execute business logic
        result = execute_business_logic(inputs)
        
        # Phase 3: Validate business logic results
        ensure_operation_successful!(result)
        
        result
      end
      
      def process_results(step, service_response, _initial_results)
        # Phase 4: Process results (optional)
        step.results = format_results(service_response)
      rescue StandardError => e
        raise Tasker::PermanentError, "Failed to process results: #{e.message}"
      end
      
      private
      
      def extract_and_validate_inputs(task, sequence, step)
        # Implementation...
      end
      
      def execute_business_logic(inputs)
        # Implementation...
      end
      
      def ensure_operation_successful!(result)
        # Implementation...
      end
      
      def format_results(response)
        # Implementation...
      end
    end
  end
end
```

### Complete YAML Example
```yaml
step_templates:
  - name: call_external_api
    handler_class: "YourNamespace::StepHandlers::ApiHandler"
    default_retry_limit: 3                     # Step template level
    default_retryable: true                    # Step template level
    depends_on_step: "validate_inputs"         # Step template level
    handler_config:                            # API config level
      url: "https://api.example.com"
      retry_delay: 2.0
      enable_exponential_backoff: true
      jitter_factor: 0.15
      headers:
        "Content-Type": "application/json"
        "Authorization": "Bearer ${API_TOKEN}"
```

## Quick Reference Links

- **Full Guide**: `spec/blog/support/STEP_HANDLER_BEST_PRACTICES.md`
- **Code Examples**: `spec/blog/support/step_handler_examples.rb`
- **Blog Examples**: `spec/blog/fixtures/post_0{1,2,3,4}_*/step_handlers/`
- **Base Classes**: `Tasker::StepHandler::Base`, `Tasker::StepHandler::Api`