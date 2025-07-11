# System Patterns: Tasker Engine Architecture

## Core Architectural Patterns

### 1. Rails Engine Architecture
Tasker is built as a **Rails Engine** that provides complete workflow orchestration while integrating seamlessly with host applications.

**Key Benefits**:
- **Isolation**: Self-contained with own models, controllers, and routes
- **Integration**: Mounts at `/tasker` with configurable authentication
- **Database**: Optional secondary database support for enterprise deployments
- **Generators**: Rails generators for rapid development

**Structure**:
```
app/
├── controllers/tasker/     # REST API and GraphQL endpoints
├── models/tasker/          # Core data models with state machines
├── jobs/tasker/            # Background job processing
├── graphql/tasker/         # GraphQL schema and resolvers
└── serializers/tasker/     # API response serialization

lib/tasker/
├── orchestration/          # Workflow execution engine
├── events/                 # Event system and subscribers
├── registry/               # Thread-safe registry systems
├── telemetry/              # Observability and metrics
└── types/                  # Dry-struct type definitions
```

### 2. Hierarchical Task Organization
**Pattern**: TaskNamespace → NamedTask → Task → WorkflowStep

```ruby
# Namespace-based organization
payments_task = Tasker::HandlerFactory.instance.get(
  'process_order',
  namespace_name: 'payments',
  version: '2.1.0'
)

inventory_task = Tasker::HandlerFactory.instance.get(
  'process_order',
  namespace_name: 'inventory',
  version: '1.5.0'
)
```

**Benefits**:
- **Isolation**: Different teams can work on same-named workflows
- **Versioning**: Multiple versions can coexist in production
- **Organization**: Clear domain boundaries and ownership

### 3. State Machine-Driven Status Management
**Pattern**: All status tracking uses Statesman gem for reliable state transitions

**Task States**:
- `pending` → `in_progress` → `complete`
- `pending` → `in_progress` → `error`
- `pending` → `cancelled`

**WorkflowStep States**:
- `pending` → `in_progress` → `complete`
- `pending` → `in_progress` → `error` → `pending` (retry)
- `pending` → `skipped`
- `error` → `resolved_manually`

**Implementation**:
```ruby
# State machine integration
def status
  if new_record?
    Tasker::Constants::TaskStatuses::PENDING
  else
    state_machine.current_state
  end
end

def state_machine
  @state_machine ||= Tasker::StateMachine::TaskStateMachine.new(
    self,
    transition_class: Tasker::TaskTransition,
    association_name: :task_transitions
  )
end
```

### 4. SQL Function-Based Performance Optimization
**Pattern**: Complex queries and calculations moved to PostgreSQL functions

**Key Functions**:
- `calculate_dependency_levels_v01()`: DAG analysis for execution order
- `get_analytics_metrics_v01()`: Performance analytics aggregation
- `get_slowest_steps_v01()`: Bottleneck identification
- `get_step_readiness_status_v01()`: Step execution readiness

**Benefits**:
- **Performance**: 2-5ms execution for complex operations
- **Consistency**: Database-level business logic
- **Scalability**: Efficient handling of large workflow graphs

### 5. Event-Driven Architecture
**Pattern**: Comprehensive event system with 56 built-in events

**Event Categories**:
```ruby
# Task lifecycle events
Tasker::Constants::TaskEvents::STARTED
Tasker::Constants::TaskEvents::COMPLETED
Tasker::Constants::TaskEvents::FAILED

# Step execution events
Tasker::Constants::StepEvents::STARTED
Tasker::Constants::StepEvents::COMPLETED
Tasker::Constants::StepEvents::FAILED

# Workflow orchestration events
Tasker::Constants::WorkflowEvents::STEPS_DISCOVERED
Tasker::Constants::WorkflowEvents::DEPENDENCIES_RESOLVED

# Observability events
Tasker::Constants::ObservabilityEvents::PERFORMANCE_METRICS
Tasker::Constants::ObservabilityEvents::HEALTH_CHECK
```

**Publisher Pattern**:
```ruby
class MyStepHandler
  include Tasker::Concerns::EventPublisher

  def process(task, sequence, step)
    publish_step_started(step)

    result = perform_business_logic(task.context)
    step.results = { data: result }

    publish_step_completed(step, operation_count: result.size)
  end
end
```

### 6. Registry System Architecture
**Pattern**: Thread-safe, enterprise-grade registry systems with structured logging

**Core Registries**:
- **HandlerFactory**: Task handler registration with namespace + version support
- **PluginRegistry**: Format-based plugin discovery
- **SubscriberRegistry**: Event subscriber management

**Thread-Safe Implementation**:
```ruby
# All registries use Concurrent::Hash for thread safety
@handlers = Concurrent::Hash.new
@plugins = Concurrent::Hash.new
@subscribers = Concurrent::Hash.new

# Structured logging with correlation IDs
def register(name, handler_class, options = {})
  log_structured(:info, 'Registry item registered', {
    entity_type: 'task_handler',
    entity_id: build_entity_id(name, options),
    entity_class: handler_class.name,
    options: options
  })
end
```

### 7. Configuration System Pattern
**Pattern**: Dry-struct based configuration with nested blocks

```ruby
Tasker::Configuration.configuration do |config|
  config.auth do |auth|
    auth.authentication_enabled = true
    auth.authenticator_class = 'MyAuthenticator'
  end

  config.execution do |exec|
    exec.min_concurrent_steps = 2
    exec.max_concurrent_steps_limit = 50
  end

  config.telemetry do |tel|
    tel.enabled = true
    tel.service_name = 'my-workflows'
  end
end
```

**Benefits**:
- **Type Safety**: Dry-struct validation and immutability
- **Organization**: Logical grouping of related settings
- **Validation**: Fail-fast configuration validation

### 8. Intelligent Caching Strategy
**Pattern**: Multi-strategy caching with distributed coordination

**Cache Store Detection**:
```ruby
# Hybrid detection system
DISTRIBUTED_CACHE_STORES = %w[
  ActiveSupport::Cache::RedisCacheStore
  ActiveSupport::Cache::MemCacheStore
  SolidCache::Store
].freeze

# Capability-based strategy selection
def coordination_strategy
  if distributed_cache_store?
    :distributed_atomic
  elsif supports_atomic_operations?
    :distributed_basic
  else
    :local_only
  end
end
```

**Adaptive TTL Calculation**:
- **HealthController**: 60 seconds (near real-time monitoring)
- **HandlersController**: 2 minutes (current registry state)
- **RuntimeGraphAnalyzer**: 90 seconds (workflow analysis)

### 9. Dynamic Concurrency Optimization
**Pattern**: System health-based concurrency calculation

```ruby
def calculate_optimal_concurrency
  # Use ConnectionPoolIntelligence for Rails-aware calculation
  intelligence_concurrency = Tasker::Orchestration::ConnectionPoolIntelligence
    .calculate_optimal_concurrency(
      current_load: fetch_system_health_data,
      connection_pool_size: fetch_connection_pool_size
    )

  # Apply execution config constraints
  [
    [intelligence_concurrency, execution_config.min_concurrent_steps].max,
    execution_config.max_concurrent_steps_limit
  ].min
end
```

**Benefits**:
- **Adaptive**: Responds to current system load
- **Safe**: Respects database connection limits
- **Performant**: Maximizes throughput within constraints

### 10. Fail-Fast Design Philosophy
**Pattern**: Explicit error handling with meaningful returns

```ruby
# ✅ PREFERRED: Explicit guard clauses
def routes_to_traces?(event_name)
  mapping = mapping_for(event_name)
  return false unless mapping  # Clear intent, explicit boolean return
  mapping.active? && mapping.routes_to_traces?
end

# ❌ AVOID: Safe navigation returning ambiguous nil
def routes_to_traces?(event_name)
  mapping = mapping_for(event_name)
  mapping&.active? && mapping&.routes_to_traces?  # Can return nil unexpectedly
end
```

**Principles**:
- Boolean methods always return `true` or `false`, never `nil`
- Error conditions are explicit with descriptive `ArgumentError` messages
- Early returns with meaningful values of expected types
- No silent failures - invalid inputs fail immediately

## Integration Patterns

### Authentication Integration
```ruby
# Pluggable authenticator pattern
class MyAuthenticator < Tasker::Authentication::BaseCoordinator
  def authenticate(request)
    # Custom authentication logic
    user = User.find_by(api_token: request.headers['Authorization'])
    user ? authentication_success(user) : authentication_failure('Invalid token')
  end
end
```

### Event Subscriber Integration
```ruby
# Custom event subscriber
class MetricsSubscriber < Tasker::Events::Subscribers::BaseSubscriber
  subscribe_to 'task.completed', 'task.failed'

  def handle_task_completed(event)
    StatsD.increment('tasker.tasks.completed')
  end

  def handle_task_failed(event)
    StatsD.increment('tasker.tasks.failed')
  end
end
```

### OpenTelemetry Integration
```ruby
# Automatic tracing integration
config.telemetry do |tel|
  tel.enabled = true
  tel.service_name = 'my-app-workflows'
  tel.service_version = '1.0.0'
end
```

## Development Patterns

### Generator Usage
```bash
# Generate complete workflow structure
rails generate tasker:task_handler OrderProcessor
rails generate tasker:authenticator JwtAuth
rails generate tasker:subscriber NotificationSubscriber
```

### Testing Patterns
```ruby
# Factory-based testing
FactoryBot.create(:tasker_task, :with_steps, step_count: 3)
FactoryBot.create(:tasker_workflow_step, :completed)

# State machine testing
expect(task.status).to eq('pending')
task.state_machine.transition_to!('in_progress')
expect(task.status).to eq('in_progress')
```

These patterns represent years of evolution and production usage, providing a solid foundation for enterprise workflow orchestration while maintaining developer productivity and system reliability.
