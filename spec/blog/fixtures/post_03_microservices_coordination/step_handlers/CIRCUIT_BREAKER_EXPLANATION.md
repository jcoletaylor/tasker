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