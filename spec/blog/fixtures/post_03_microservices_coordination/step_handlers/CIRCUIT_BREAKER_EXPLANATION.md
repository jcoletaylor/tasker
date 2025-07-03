# Circuit Breaker Pattern in Chapter 3

## Important Architecture Decision

This chapter originally implemented custom circuit breaker patterns through an in-memory `CircuitBreakerPattern` concern. However, during development, we realized that **Tasker already provides superior circuit breaker functionality** through its SQL-driven retry architecture.

## Why Tasker's Approach is Better

### Traditional Circuit Breakers vs Tasker
| Aspect | Custom Circuit Breaker | Tasker's Architecture |
|--------|----------------------|----------------------|
| **State Storage** | In-memory (volatile) | Database (persistent) |
| **Coordination** | Per-process | Distributed across workers |
| **Observability** | Custom metrics | SQL queries + structured logging |
| **Recovery** | Time-based | Intelligent backoff + dependency-aware |
| **Configuration** | Global per service | Per-step + per-task customization |

## How Tasker Implements Circuit Breaker Logic

### 1. Fail-Fast Through Error Classification
```ruby
# Permanent failures - circuit stays "open" indefinitely
raise Tasker::PermanentError.new(
  "Invalid request: #{response.body}",
  error_code: 'VALIDATION_ERROR'
)

# Transient failures - circuit will retry after backoff
raise Tasker::RetryableError.new(
  "Service unavailable: #{response.status}",
  retry_after: response.headers['retry-after']&.to_i
)
```

### 2. Intelligent Backoff (The "Open Circuit" State)
- SQL-driven backoff calculation with exponential backoff + jitter
- Configurable per step through `retry_limit` and `handler_config`
- Persistent across process restarts and deployments

### 3. Automatic Recovery (The "Half-Open" State)
- Steps become `retry_eligible = true` when backoff period expires
- Tasker automatically attempts execution when dependencies are satisfied
- No manual circuit state management required

## Updated Implementation

Our step handlers now use Tasker's native error handling:

```ruby
class CreateUserAccountHandler < ApiBaseHandler
  def process(task, sequence, step)
    # No custom circuit breaker logic needed!
    response = connection.post("#{service_url}/users") do |req|
      req.body = user_data.to_json
      req.headers.merge!(enhanced_default_headers)
    end

    # Let Tasker's error classification handle circuit breaker logic
    case response.status
    when 201
      # Success case
    else
      handle_microservice_response(response, 'user_service')
    end
  end
end
```

## Benefits in Practice

1. **Durability**: Circuit state survives process restarts
2. **Distributed Coordination**: Multiple workers coordinate through database
3. **Rich Observability**: SQL queries show circuit health across all services
4. **Dependency Awareness**: Circuit decisions consider workflow dependencies
5. **Type Safety**: Explicit error classification prevents retry of permanent failures

## Key Insight

**Persistence + distributed coordination > in-memory circuit objects** for workflow orchestration systems.

Tasker's architecture demonstrates that sophisticated distributed systems patterns don't always require custom implementations - sometimes the framework already provides a superior solution.

# Why Tasker Doesn't Need Custom Circuit Breakers

## The Problem with Traditional Circuit Breaker Implementations

Most microservices architectures implement circuit breakers as in-memory objects within each service:

```ruby
# ❌ Traditional approach - DON'T do this with Tasker
class MyService
  def call_external_api
    circuit_breaker.call do
      # Make API call
    end
  end

  private

  def circuit_breaker
    @circuit_breaker ||= CircuitBreaker.new(
      failure_threshold: 5,
      recovery_timeout: 60
    )
  end
end
```

**Problems with this approach:**
- **Volatile state**: Circuit breaker state is lost on process restart
- **No coordination**: Multiple workers have separate circuit breaker states
- **Limited observability**: Hard to query circuit breaker health across services
- **Duplicate logic**: Every service reimplements the same patterns

## How Tasker Solves Circuit Breaker Patterns at the Framework Level

Tasker implements **distributed, persistent circuit breaker functionality** through its SQL-driven retry architecture:

### 1. Fail-Fast Through Error Classification

```ruby
# ✅ Tasker approach - Proper error classification
class CreateUserAccountHandler < Tasker::StepHandler::Api
  def process(task, sequence, step)
    response = call_user_service(user_data)

    case response.status
    when 400, 422
      # PERMANENT failures - circuit stays "open" indefinitely
      raise Tasker::PermanentError.new(
        "Validation failed: #{response.body}",
        error_code: 'VALIDATION_ERROR'
      )
    when 429, 500..599
      # TRANSIENT failures - circuit will retry with intelligent backoff
      raise Tasker::RetryableError.new(
        "Service unavailable: #{response.status}",
        retry_after: response.headers['retry-after']&.to_i
      )
    end
  end
end
```

### 2. Intelligent Backoff (The "Open Circuit" State)

Tasker's SQL-driven backoff calculation provides sophisticated circuit breaker logic:

```sql
-- From get_step_readiness_status_v01.sql
CASE
  WHEN ws.backoff_request_seconds IS NOT NULL THEN
    ws.last_attempted_at + (ws.backoff_request_seconds * interval '1 second') <= NOW()
  WHEN last_failure.created_at IS NOT NULL THEN
    last_failure.created_at + (LEAST(power(2, ws.attempts) * interval '1 second', interval '30 seconds')) <= NOW()
  ELSE true
END as retry_eligible
```

**Benefits over traditional circuit breakers:**
- **Persistent across restarts**: State stored in database, not memory
- **Distributed coordination**: Multiple workers respect the same backoff timing
- **Configurable per step**: Different APIs can have different backoff strategies
- **Server-directed backoff**: Respects `retry-after` headers from failing services

### 3. Automatic Recovery (The "Half-Open" State)

```ruby
# Tasker automatically handles recovery
step_status = Tasker::StepReadinessStatus.for_task(task.id)
ready_steps = step_status.select(&:ready_for_execution)

# Steps become eligible for retry when:
# 1. Backoff period has expired (retry_eligible = true)
# 2. Dependencies are satisfied
# 3. Step is in retryable state
```

## Circuit Breaker States in Tasker Terms

| Traditional Circuit Breaker | Tasker Equivalent | Condition |
|----------------------------|-------------------|-----------|
| **Closed** (healthy) | `ready_for_execution = true` | No recent failures, dependencies satisfied |
| **Open** (failing fast) | `retry_eligible = false` | Within backoff period or permanent failure |
| **Half-Open** (testing) | `retry_eligible = true` | Backoff period expired, ready for retry |

## Observability: SQL Queries vs Custom Metrics

### Traditional Circuit Breaker Observability
```ruby
# ❌ Limited observability
circuit_breaker.failure_count  # Only current process
circuit_breaker.state          # Only current process
circuit_breaker.last_failure   # Only current process
```

### Tasker's Rich Observability
```sql
-- ✅ Rich, distributed observability
SELECT
  name,
  current_state,
  retry_eligible,
  next_retry_at,
  attempts,
  backoff_request_seconds
FROM get_step_readiness_status(task_id)
WHERE current_state = 'error';

-- Monitor circuit breaker patterns across all services
SELECT
  name,
  COUNT(*) as failure_count,
  AVG(attempts) as avg_attempts,
  MAX(backoff_request_seconds) as max_backoff
FROM get_step_readiness_status(task_id)
WHERE current_state = 'error'
GROUP BY name;
```

## Configuration: Per-Step vs Global

### Traditional Circuit Breakers
```ruby
# ❌ Global configuration per service
CircuitBreaker.new(
  failure_threshold: 5,    # Same for all operations
  recovery_timeout: 60     # Same for all operations
)
```

### Tasker's Flexible Configuration
```yaml
# ✅ Per-step configuration
steps:
  - name: create_user_account
    retry_limit: 5          # Circuit opens after 5 failures
    retryable: true
    handler_config:
      timeout: 30

  - name: send_billing_notification
    retry_limit: 3          # More sensitive - money involved
    retryable: true
    handler_config:
      timeout: 60
```

## Key Architectural Insights

### 1. Persistence > Memory
**Traditional**: Circuit breaker state is lost on process restart
**Tasker**: Circuit breaker state persists across deployments and restarts

### 2. Distributed Coordination > Per-Process State
**Traditional**: Each worker has its own circuit breaker state
**Tasker**: All workers coordinate through shared database state

### 3. Framework-Level > Application-Level
**Traditional**: Each service implements its own circuit breaker logic
**Tasker**: Framework provides sophisticated circuit breaker patterns automatically

### 4. Typed Errors > Binary Success/Failure
**Traditional**: Circuit breakers only know "success" or "failure"
**Tasker**: `PermanentError` vs `RetryableError` provides intelligent circuit behavior

## Conclusion

Tasker's architecture demonstrates that **sophisticated distributed systems patterns don't always require custom implementations**. By leveraging:

- **SQL-driven retry logic** for persistence and coordination
- **Typed error classification** for intelligent failure handling
- **Dependency-aware scheduling** for workflow context
- **Rich observability** through database queries

Tasker provides **superior circuit breaker functionality** compared to traditional in-memory implementations, while reducing code complexity and improving system reliability.

**The key insight**: *Framework-level circuit breakers > Application-level circuit breakers* for distributed workflow orchestration systems.
