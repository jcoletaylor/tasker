# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Setup & Installation
- `bundle install` - Install dependencies
- `bundle exec rails tasker:install:migrations` - Install database migrations
- `bundle exec rails tasker:install:database_objects` - Copy database views and functions
- `bundle exec rails db:migrate` - Run database migrations
- `bundle exec rails tasker:setup` - Initialize configuration and directories

### Testing
- `bundle exec rspec` - Run full test suite
- `bundle exec rspec spec/path/to/spec.rb` - Run specific test file
- `bundle exec rspec spec/path/to/spec.rb:123` - Run specific test at line

### Linting & Quality
- `bundle exec rubocop` - Run RuboCop linter
- `bundle exec rubocop -a` - Auto-fix RuboCop violations
- `bundle exec brakeman` - Run security analysis

### Generators
- `rails generate tasker:task_handler NAME` - Generate new task handler with YAML config
- `rails generate tasker:authenticator NAME` - Generate authentication strategy
- `rails generate tasker:authorization_coordinator NAME` - Generate authorization coordinator
- `rails generate tasker:subscriber NAME` - Generate event subscriber

### Metrics & Telemetry
- `bundle exec rails tasker:export_metrics[FORMAT]` - Schedule metrics export (async)
- `bundle exec rails tasker:export_metrics_now[FORMAT]` - Export metrics immediately
- `bundle exec rails tasker:sync_metrics` - Sync metrics to cache
- `bundle exec rails tasker:metrics_status` - Show metrics configuration status

## Architecture Overview

Tasker is a **Rails engine** for enterprise-grade workflow orchestration with these core components:

### Core Architecture
- **Rails Engine**: Mounted at `/tasker` providing REST API, GraphQL, and health endpoints
- **ActiveRecord Models**: Task, WorkflowStep, TaskNamespace with state machines via Statesman
- **SQL Functions**: High-performance PostgreSQL functions for orchestration logic
- **Event System**: 56 built-in events with custom subscriber support
- **Registry Systems**: Thread-safe HandlerFactory, PluginRegistry, SubscriberRegistry

### Key Components
- **TaskNamespaces**: Hierarchical organization (`payments`, `inventory`, `notifications`)
- **TaskHandlers**: Ruby classes defining workflow coordination logic
- **StepHandlers**: Individual step implementation classes
- **YAML Configuration**: Declarative step templates with dependencies
- **State Machines**: Task and WorkflowStep state transitions
- **Authentication/Authorization**: Pluggable security with GraphQL operation-level permissions

### Directory Structure
- `app/` - Rails engine MVC components (controllers, models, jobs, GraphQL)
- `lib/tasker/` - Core engine logic (orchestration, events, telemetry, types)
- `db/` - Migrations, SQL functions, and database views
- `spec/` - Comprehensive test suite with dummy Rails app
- `docs/` - Extensive documentation including API guides

### Database Architecture
- **PostgreSQL Required**: Uses custom SQL functions for performance
- **Views**: Optimized views for task execution contexts and step readiness
- **Functions**: Batch operations for dependency resolution and health monitoring
- **Indexes**: Performance-optimized indexes for concurrent execution

### Security Model
- **Authentication**: Pluggable authenticators (JWT, Devise, API tokens, custom)
- **Authorization**: Resource-based permissions with coordinator pattern
- **GraphQL Security**: Automatic operation-to-permission mapping
- **REST API Security**: Configurable authentication on all endpoints

### Event System
Built-in events include task lifecycle, step transitions, system health, and telemetry with structured logging and correlation IDs.

## Configuration Patterns

### Engine Configuration
Located in `config/initializers/tasker.rb`:
- Database connection settings
- Authentication/authorization setup  
- Telemetry and metrics configuration
- Health monitoring configuration

### Task Handler Organization
- YAML files in `config/tasker/tasks/` define step templates and dependencies
- Ruby classes in `app/tasker/` implement coordination logic
- Step handlers organize business logic by domain

### Namespace + Versioning
Task handlers support semantic versioning and namespace organization:
```yaml
name: process_order
namespace_name: payments
version: 2.1.0
```

## Testing Patterns

### Test Infrastructure
- **RSpec**: Primary testing framework with custom helpers
- **FactoryBot**: Comprehensive factories for all models
- **State Machine Testing**: Dedicated helpers for testing transitions
- **Telemetry Testing**: Mock integrations and event verification
- **Database Function Testing**: Direct SQL function testing

### Key Test Types
- Unit tests for individual components
- Integration tests for workflow orchestration
- API tests for REST and GraphQL endpoints
- Security tests for authentication/authorization
- Performance tests for SQL functions

## Performance Considerations

### SQL Functions
High-performance PostgreSQL functions handle:
- Dependency level calculations
- Step readiness status determination
- Task execution context batch operations
- System health metrics

### Caching Strategy
- Intelligent cache management with multiple backend support
- 15-second health endpoint caching
- Metrics synchronization for export operations
- Thread-safe registry caching

### Concurrency
- Thread-safe registry operations using `Concurrent::Hash`
- Concurrent step execution with dependency resolution
- Connection pooling for orchestration operations

## Common Workflows

### Adding New Task Handler
1. Generate handler: `rails generate tasker:task_handler NAME`
2. Edit YAML config in `config/tasker/tasks/`
3. Implement step handlers in generated Ruby classes
4. Add tests following existing patterns

### Adding Custom Authentication
1. Generate authenticator: `rails generate tasker:authenticator NAME`
2. Implement authentication interface methods
3. Configure in `config/initializers/tasker.rb`
4. Add authorization coordinator if needed

### Adding Event Subscribers
1. Generate subscriber: `rails generate tasker:subscriber NAME`
2. Implement event handling methods
3. Register subscriber in initializer
4. Test event integration

### Debugging Workflows
- Check task state via REST API: `GET /tasker/tasks/:id`
- Monitor step execution: `GET /tasker/workflow_steps/:id`
- Review health status: `GET /tasker/health/status`
- Enable structured logging for detailed traces

## Version Release Workflow

When ready to commit and release a new version, follow this systematic workflow:

### Pre-Release Steps
1. **Determine Version Type**: Review changes to decide if major, minor, or patch level revision
   - Major: Breaking API changes, significant architectural changes
   - Minor: New features, backwards-compatible additions
   - Patch: Bug fixes, performance improvements, documentation, behind-the-scenes enhancements

2. **Update Version File**: Modify `lib/tasker/version.rb` to reflect new semantic version

3. **Update Version References**: Find and update version references in:
   - Documentation files (excluding YARD docs - handled separately)
   - Script files
   - Configuration files
   - README and other markdown files

### Build and Quality Checks
4. **Rebuild Dependencies**: `bundle exec gem build` (rebuilds Gemfile.lock with new version)

5. **Clean Build Artifacts**: `rm` the produced .gem file (don't publish until merged to main)

6. **Code Quality**: `bundle exec rubocop -A` (auto-fix all style issues)

7. **Documentation**: `bundle exec yard` (regenerate API documentation)

8. **Database Preparation**: `bundle exec rails db:migrate db:test:prepare`

9. **Full Test Suite**: `bundle exec rspec -f d` (run all tests with detailed output)

### Release Process
10. **Manual Git Operations**: User handles `git add`, `git commit`, and `git push`

11. **Create Pull Request**: Open PR on GitHub

12. **PR Documentation**: Create `PR_DESCRIPTION.md` with accomplishments and version changes

### Post-Merge (GitHub)
13. **Tag Release**: Create GitHub release with semantic version tag
14. **Publish Gem**: Build and publish to RubyGems after all tests pass
15. **Update Documentation**: Deploy updated docs if applicable

## Current Development Status

### Recent Achievements (2025)
- **Complete Infrastructure Repair**: Achieved 1,692 tests passing (0 failures) from 108 failing tests
- **Phase 2.1 Cache Strategy**: Implemented intelligent cache management with distributed coordination
- **Integration Validation**: Completed Jaeger and Prometheus validation scripts with 100% pass rates
- **Registry System Consolidation**: Thread-safe operations with structured logging
- **Demo Application Builder**: Comprehensive template system for rapid development

### Architecture Principles

#### Fail-Fast Design Philosophy
Tasker implements explicit fail-fast principles throughout:

```ruby
# ✅ PREFERRED: Explicit guard clauses with meaningful returns
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

**Key Patterns**:
- Boolean methods always return `true` or `false`, never `nil`
- Error conditions are explicit with descriptive `ArgumentError` messages
- Early returns with meaningful values of expected types
- No silent failures - invalid inputs fail immediately

#### Constants vs Configuration Framework
Strategic separation enables infrastructure consistency with workload flexibility:

**CONSTANTS (Infrastructure)**:
- Cache key prefixes consistent across deployments
- Component naming aligned with Tasker conventions
- Cache store class names for capability detection

**CONFIGURABLE (Algorithm Parameters)**:
- TTL bounds for different cache store characteristics
- Smoothing factors and decay rates for workload tuning
- Retry limits and backoff strategies

#### Performance Optimization Patterns
- **Dynamic Concurrency**: Intelligent calculation based on system health metrics
- **Distributed Coordination**: Multi-strategy coordination (Redis, Memcached, File/Memory)
- **Cache TTL Optimization**: Operationally-tuned values (60s health, 90s workflow analysis)
- **SQL Function Performance**: 2-5ms execution for complex operations

#### Performance Optimization Status
- **Phase 1 Complete**: Dynamic concurrency, memory leak prevention, and query optimization fully implemented
- **Memory Management**: Enterprise-grade future cleanup with intelligent GC (StepExecutor:685-931)
- **Query Optimization**: 3-layer index strategy with N+1 prevention (migrations 2025-06-03 to 2025-06-28)
- **Dynamic Concurrency**: System health-based concurrency calculation (StepExecutor:97-683)
- **Test Validation**: 1,692 passing tests confirm comprehensive performance infrastructure