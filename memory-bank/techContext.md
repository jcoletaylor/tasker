# Technical Context: Tasker Engine Technology Stack

## Core Technology Stack

### Ruby & Rails Requirements
- **Ruby**: 3.2+ (leverages modern Ruby features and performance improvements)
- **Rails**: 7.2+ (Rails engine architecture with modern ActiveRecord features)
- **Database**: PostgreSQL (required for SQL functions and advanced features)
- **Background Jobs**: ActiveJob compatible (Sidekiq recommended for production)

### Key Dependencies

#### Core Runtime Dependencies
```ruby
# Essential gems from gemspec
gem 'concurrent-ruby', '~> 1.3.5'  # Thread-safe data structures
gem 'dry-events', '~> 1.0'         # Event system foundation
gem 'dry-types', '~> 1.7'          # Type system and validation
gem 'dry-struct', '~> 1.6'         # Immutable configuration objects
gem 'dry-validation', '~> 1.10'    # Input validation
gem 'statesman', '~> 12.0'         # State machine management
```

#### Rails Engine Dependencies
```ruby
# Rails engine specific
gem 'rails', '>= 7.2.0'
gem 'graphql', '~> 2.3'            # GraphQL API support
gem 'graphql-rails_logger', '~> 1.2'  # GraphQL logging
gem 'kaminari', '~> 1.2'           # Pagination support
```

#### Development & Testing
```ruby
# Development tools
gem 'rubocop', '~> 1.74'           # Code style and quality
gem 'yard', '~> 0.9'               # Documentation generation
gem 'rspec-rails', '~> 7.1'        # Testing framework
gem 'factory_bot_rails', '~> 6.4'  # Test data factories
gem 'simplecov', '~> 0.22'         # Code coverage
```

#### Optional Production Dependencies
```ruby
# Cache stores (optional)
gem 'redis', '~> 5.0'              # For RedisCacheStore
gem 'dalli', '~> 3.2'              # For MemCacheStore
gem 'solid_cache', '~> 1.0'        # For SolidCache

# Background processing (recommended)
gem 'sidekiq', '~> 7.3'            # Background job processing
gem 'solid_queue', '~> 1.1'        # Alternative job backend

# Observability (optional)
gem 'opentelemetry-instrumentation-all', '~> 0.74.0'  # Distributed tracing
```

## Database Architecture

### PostgreSQL Requirements
Tasker Engine **requires PostgreSQL** due to its use of advanced database features:

#### SQL Functions
High-performance functions for workflow orchestration:
```sql
-- Dependency analysis and execution ordering
CREATE OR REPLACE FUNCTION calculate_dependency_levels_v01()
RETURNS TABLE(workflow_step_id bigint, dependency_level integer);

-- Performance analytics aggregation
CREATE OR REPLACE FUNCTION get_analytics_metrics_v01(since_time timestamp)
RETURNS TABLE(metric_name text, metric_value numeric);

-- Step readiness calculation
CREATE OR REPLACE FUNCTION get_step_readiness_status_v01(task_ids bigint[])
RETURNS TABLE(workflow_step_id bigint, ready_for_execution boolean);
```

#### Database Views
Optimized views for complex queries:
```sql
-- Step DAG relationships for dependency analysis
CREATE VIEW tasker_step_dag_relationships_v01 AS
SELECT workflow_step_id, parent_count, child_count, dependency_level
FROM workflow_steps_with_dag_analysis;
```

#### Advanced Features Used
- **JSONB columns**: For flexible context and results storage
- **GIN indexes**: For efficient JSONB querying
- **Window functions**: For analytics and ranking
- **CTEs**: For complex dependency analysis
- **Array operations**: For batch processing

### Database Configuration
```ruby
# Primary database (shared with host app)
production:
  primary:
    adapter: postgresql
    database: my_app_production

# Optional: Dedicated Tasker database
production:
  tasker:
    adapter: postgresql
    database: my_app_tasker_production
```

## Performance Characteristics

### SQL Function Performance
- **Dependency Analysis**: 2-5ms for complex workflow graphs
- **Analytics Queries**: Sub-10ms for performance metrics
- **Step Readiness**: 1-3ms for batch readiness calculation
- **Health Metrics**: <5ms for system health aggregation

### Concurrency & Scaling
```ruby
# Dynamic concurrency optimization
config.execution do |exec|
  exec.min_concurrent_steps = 2
  exec.max_concurrent_steps_limit = 50
  exec.concurrency_cache_duration = 30  # seconds
end
```

**Scaling Characteristics**:
- **Thread-Safe**: All registry systems use `Concurrent::Hash`
- **Connection Pool Aware**: Respects ActiveRecord connection limits
- **Memory Efficient**: Intelligent garbage collection for large batches
- **Database Optimized**: Minimal N+1 queries through eager loading

### Caching Strategy
```ruby
# Multi-tier caching with adaptive TTL
CACHE_CONFIGURATIONS = {
  health_status: { ttl: 60.seconds, strategy: :distributed_atomic },
  handler_registry: { ttl: 2.minutes, strategy: :distributed_basic },
  workflow_analysis: { ttl: 90.seconds, strategy: :local_with_fallback }
}
```

## Security Architecture

### Authentication Strategies
```ruby
# Pluggable authentication system
config.auth do |auth|
  auth.authentication_enabled = true
  auth.authenticator_class = 'MyAuthenticator'
end

# Built-in authenticator types
class JwtAuthenticator < Tasker::Authentication::BaseCoordinator
  def authenticate(request)
    token = extract_jwt_token(request)
    payload = JWT.decode(token, secret_key, true, algorithm: 'HS256')
    user = User.find(payload['user_id'])
    authentication_success(user)
  rescue JWT::DecodeError
    authentication_failure('Invalid JWT token')
  end
end
```

### Authorization Framework
```ruby
# Resource-based authorization
config.auth do |auth|
  auth.authorization_enabled = true
  auth.authorization_coordinator_class = 'MyAuthorizationCoordinator'
end

# Automatic GraphQL permission mapping
# query { tasks } → requires 'tasker.task:index' permission
# mutation { createTask } → requires 'tasker.task:create' permission
```

## Observability & Monitoring

### OpenTelemetry Integration
```ruby
config.telemetry do |tel|
  tel.enabled = true
  tel.service_name = 'my-app-workflows'
  tel.service_version = '1.0.0'
  tel.environment = Rails.env
end
```

**Automatic Instrumentation**:
- **Task Execution**: Complete workflow tracing
- **Step Processing**: Individual step spans with timing
- **Database Operations**: SQL function execution tracing
- **Event Publishing**: Event system observability

### Health Monitoring
```ruby
# Health check endpoints
GET /tasker/health/ready    # Kubernetes readiness probe
GET /tasker/health/live     # Kubernetes liveness probe
GET /tasker/health/status   # Detailed system metrics
```

**Health Metrics**:
- Database connectivity and query performance
- Registry system health and statistics
- Active task and step counts
- Error rates and retry statistics

### Structured Logging
```ruby
# Correlation ID tracking
include Tasker::Concerns::StructuredLogging

log_structured(:info, 'Task execution started', {
  task_id: task.task_id,
  step_count: viable_steps.size,
  processing_mode: 'concurrent',
  correlation_id: current_correlation_id
})
```

## Development Environment

### Required Tools
- **PostgreSQL**: Local development database
- **Redis**: Optional for caching (development can use memory cache)
- **Bundler**: Dependency management
- **Git**: Version control (required for gem installation)

### Development Commands
```bash
# Setup
bundle install
bundle exec rails tasker:install:migrations
bundle exec rails tasker:install:database_objects
bundle exec rails db:migrate
bundle exec rails tasker:setup

# Testing
bundle exec rspec
bundle exec rubocop
bundle exec brakeman  # Security analysis

# Documentation
bundle exec yard      # Generate API docs
```

### Generators
```bash
# Workflow development
rails generate tasker:task_handler NAME
rails generate tasker:authenticator NAME
rails generate tasker:authorization_coordinator NAME
rails generate tasker:subscriber NAME
```

## Production Deployment

### Container Requirements
```dockerfile
# Minimal container requirements
FROM ruby:3.2-alpine
RUN apk add --no-cache postgresql-dev build-base
# ... standard Rails deployment
```

### Environment Variables
```bash
# Database
DATABASE_URL=postgresql://user:pass@host:5432/dbname
TASKER_DATABASE_URL=postgresql://user:pass@host:5432/tasker_db  # Optional

# Redis (optional)
REDIS_URL=redis://redis:6379/0

# Observability (optional)
OTEL_SERVICE_NAME=my-app-workflows
OTEL_EXPORTER_OTLP_ENDPOINT=http://jaeger:14268/api/traces
```

### Kubernetes Deployment
```yaml
# Health check configuration
livenessProbe:
  httpGet:
    path: /tasker/health/live
    port: 3000
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /tasker/health/ready
    port: 3000
  initialDelaySeconds: 5
  periodSeconds: 5
```

## Version Compatibility

### Ruby Compatibility
- **Ruby 3.2+**: Full support with modern features
- **Ruby 3.1**: Compatible but missing some optimizations
- **Ruby 3.0**: Not recommended (missing required features)

### Rails Compatibility
- **Rails 7.2+**: Full support with all features
- **Rails 7.1**: Compatible with minor limitations
- **Rails 7.0**: Not supported (missing required engine features)

### Database Compatibility
- **PostgreSQL 14+**: Recommended for optimal performance
- **PostgreSQL 13**: Supported with all features
- **PostgreSQL 12**: Supported but some functions may be slower
- **MySQL/SQLite**: Not supported (requires PostgreSQL-specific features)

This technical foundation provides enterprise-grade reliability while maintaining developer productivity through modern Ruby and Rails practices.
