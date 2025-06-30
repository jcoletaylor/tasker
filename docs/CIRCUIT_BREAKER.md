# Circuit Breaker Pattern in Tasker

## Overview

Tasker implements circuit breaker functionality through its **distributed, SQL-driven retry architecture** rather than through traditional in-memory circuit breaker objects. This approach provides better durability, observability, and coordination across multiple worker processes.

## Why Circuit Breaker Patterns Matter

Circuit breakers prevent cascading failures by:
- **Failing fast** when services are unavailable
- **Backing off** to reduce load on failing services  
- **Automatically recovering** when services become healthy
- **Providing observability** into failure patterns

## How Tasker Implements Circuit Breaker Logic

### 1. Fail-Fast Through Step State Management

```ruby
# Tasker automatically fails fast through step state transitions
step.current_state  # 'pending' → 'in_progress' → 'complete' | 'error'

# Failed steps are immediately marked as 'error' state
# No further processing attempts until retry conditions are met
```

### 2. Intelligent Backoff (The "Open Circuit" State)

```sql
-- SQL-driven backoff calculation (get_step_readiness_status_v01.sql)
CASE
  WHEN ws.backoff_request_seconds IS NOT NULL AND ws.last_attempted_at IS NOT NULL THEN
    ws.last_attempted_at + (ws.backoff_request_seconds * interval '1 second') <= NOW()
  WHEN last_failure.created_at IS NOT NULL THEN
    last_failure.created_at + (LEAST(power(2, COALESCE(ws.attempts, 1)) * interval '1 second', interval '30 seconds')) <= NOW()
  ELSE true
END as retry_eligible
```

**Benefits over traditional circuit breakers:**
- **Persistent across restarts** - State stored in database, not memory
- **Distributed coordination** - Multiple workers respect the same backoff timing
- **Configurable per step** - Different services can have different backoff strategies
- **Observable through SQL** - Easy to query and monitor backoff states

### 3. Automatic Recovery (The "Half-Open" State)

```ruby
# When backoff period expires, step becomes eligible for retry
step_status = Tasker::StepReadinessStatus.for_task(task.id)
ready_steps = step_status.select(&:ready_for_execution)

# Tasker automatically attempts execution when:
# 1. Backoff period has expired (retry_eligible = true)
# 2. Dependencies are satisfied
# 3. Step is in retryable state
```

### 4. Error Classification with RetryableError vs PermanentError

```ruby
# In your API handlers - explicit error classification
case response.status
when 400, 422
  # Permanent failures - circuit stays "open" indefinitely
  raise Tasker::PermanentError.new(
    "Invalid request: #{response.body}",
    error_code: 'VALIDATION_ERROR'
  )
when 429, 503
  # Transient failures - circuit will retry after backoff
  raise Tasker::RetryableError.new(
    "Service unavailable: #{response.status}",
    retry_after: response.headers['retry-after']&.to_i
  )
end
```

## Comparison: Traditional vs Tasker Circuit Breaker

| Aspect | Traditional Circuit Breaker | Tasker's Architecture |
|--------|----------------------------|----------------------|
| **State Storage** | In-memory (volatile) | Database (persistent) |
| **Coordination** | Per-process | Distributed across workers |
| **Observability** | Custom metrics | SQL queries + structured logging |
| **Recovery** | Time-based | Intelligent backoff + dependency-aware |
| **Configuration** | Global per service | Per-step + per-task customization |
| **Failure Classification** | Binary (fail/success) | Typed errors (RetryableError, PermanentError) |

## Key Components

### 1. SQL Functions for Circuit Logic

- **`get_step_readiness_status()`** - Determines if steps are ready for execution
- **Backoff calculation** - Exponential backoff with jitter and caps
- **Dependency resolution** - Ensures proper execution order

### 2. Orchestration Components

```ruby
# lib/tasker/orchestration/backoff_calculator.rb
@backoff_calculator.calculate_and_apply_backoff(step, error_context)

# lib/tasker/orchestration/task_finalizer.rb  
finalizer.reenqueue_task_with_context(task, context, reason: :awaiting_dependencies)
```

### 3. Error Handling Hierarchy

```ruby
Tasker::ProceduralError
├── Tasker::RetryableError     # Transient failures (circuit will retry)
└── Tasker::PermanentError     # Permanent failures (circuit stays open)
```

## Circuit States in Tasker Terms

| Circuit Breaker State | Tasker Equivalent | Condition |
|----------------------|-------------------|-----------|
| **Closed** (healthy) | `ready_for_execution = true` | No recent failures, dependencies satisfied |
| **Open** (failing fast) | `retry_eligible = false` | Within backoff period or max retries exceeded |
| **Half-Open** (testing) | `retry_eligible = true` | Backoff period expired, ready for retry attempt |

## Monitoring and Observability

### SQL Queries for Circuit State

```sql
-- Check "open circuit" steps (failing fast)
SELECT workflow_step_id, name, current_state, next_retry_at, attempts
FROM get_step_readiness_status(task_id)
WHERE current_state = 'error' AND retry_eligible = false;

-- Check "half-open" steps (ready to test)
SELECT workflow_step_id, name, next_retry_at, attempts  
FROM get_step_readiness_status(task_id)
WHERE current_state = 'error' AND retry_eligible = true;

-- Monitor backoff patterns
SELECT name, attempts, backoff_request_seconds, next_retry_at
FROM get_step_readiness_status(task_id)
WHERE backoff_request_seconds IS NOT NULL;
```

### Structured Logging Events

```json
{
  "component": "backoff_calculator",
  "event_type": "backoff",
  "backoff_seconds": 30,
  "backoff_type": "server_requested",
  "step_id": 12442,
  "attempts": 2
}
```

## Best Practices

### 1. Use Typed Errors in API Handlers

```ruby
class MyApiHandler < Tasker::StepHandler::Api
  def process(task, sequence, step)
    response = connection.post('/api/endpoint', task.context)
    
    case response.status
    when 429
      # Server tells us exactly when to retry
      retry_after = response.headers['retry-after']&.to_i || 60
      raise Tasker::RetryableError.new(
        "Rate limited",
        retry_after: retry_after
      )
    when 500..599
      # Let Tasker's exponential backoff handle timing
      raise Tasker::RetryableError.new("Server error: #{response.status}")
    when 400..499
      # Don't retry client errors
      raise Tasker::PermanentError.new(
        "Client error: #{response.status}",
        error_code: 'CLIENT_ERROR'
      )
    end
    
    response
  end
end
```

### 2. Configure Appropriate Retry Limits

```yaml
# config/tasker/tasks/my_api_task.yml
steps:
  - name: call_external_api
    retry_limit: 5  # Circuit "opens" after 5 failures
    retryable: true
```

### 3. Monitor Circuit Health

```ruby
# Check overall task health
context = Tasker::Functions::FunctionBasedTaskExecutionContext.find(task_id)
puts "Health: #{context.health_status}"
puts "Failed steps: #{context.failed_steps}"
puts "Ready steps: #{context.ready_steps}"
```

## Why This Architecture is Superior

1. **Durability** - Circuit state survives process restarts and deployments
2. **Distributed Coordination** - Multiple workers coordinate through database state
3. **Granular Control** - Different APIs can have different backoff strategies
4. **Built-in Observability** - Rich SQL queries and structured logging
5. **Dependency Awareness** - Circuit decisions consider workflow dependencies
6. **Type Safety** - Explicit error classification prevents retry of permanent failures

## Conclusion

Tasker's architecture already implements sophisticated circuit breaker patterns through its **SQL-driven, distributed retry system**. This approach provides better durability, observability, and coordination than traditional in-memory circuit breakers, while maintaining the same core benefits of failing fast, backing off intelligently, and recovering automatically.

The key insight is that **persistence + distributed coordination > in-memory circuit objects** for workflow orchestration systems.