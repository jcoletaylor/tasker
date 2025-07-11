# Technical Context

## Technology Stack

### Core Technologies
- **Ruby**: 3.4.2 (latest stable)
- **Rails**: 7.2.2.1 (Rails engine architecture)
- **PostgreSQL**: Primary database with advanced SQL functions
- **ActiveJob**: Background job processing integration
- **RSpec**: Testing framework with comprehensive test suite

### Key Dependencies
```ruby
# Core Rails dependencies
gem 'rails', '~> 7.2.2'
gem 'pg', '~> 1.1'

# State management
gem 'statesman', '~> 12.0'

# Background processing
gem 'sidekiq', '~> 7.0'

# Testing
gem 'rspec-rails', '~> 7.1'
gem 'factory_bot_rails', '~> 6.5'

# Development
gem 'rubocop', '~> 1.60'
gem 'yard', '~> 0.9'
```

### Database Schema
- **Tasks**: Core workflow instances
- **WorkflowSteps**: Individual step instances within tasks
- **TaskTransitions**: State machine history for tasks
- **WorkflowStepTransitions**: State machine history for steps
- **WorkflowStepEdges**: DAG relationships between steps
- **NamedTasks/NamedSteps**: Template definitions

## Development Setup

### Environment Requirements
- Ruby 3.4.2 (managed via rbenv)
- PostgreSQL 12+ with function support
- Redis (for Sidekiq in production)
- Bundler 2.4+

### Local Development
```bash
# Setup
bundle install
bundle exec rails db:create db:migrate

# Run tests
bundle exec rspec

# Generate documentation
bundle exec yard doc

# Linting
bundle exec rubocop
```

### Database Functions
Critical SQL functions must be updated in both development and production:
```bash
# Update functions after changes
bundle exec rails runner "ActiveRecord::Base.connection.execute(File.read('db/functions/get_step_readiness_status_v01.sql'))"
bundle exec rails runner "ActiveRecord::Base.connection.execute(File.read('db/functions/get_step_readiness_status_batch_v01.sql'))"
```

## Technical Constraints

### Performance Requirements
- **Step Readiness**: <100ms for 1000+ step workflows
- **Concurrent Execution**: Max 3 concurrent steps per task (database connection limits)
- **Memory Usage**: Efficient processing without memory leaks
- **Database Connections**: Connection pooling for concurrent operations

### Compatibility Requirements
- **Ruby**: 3.0+ (uses modern Ruby features)
- **Rails**: 7.0+ (Rails engine pattern)
- **PostgreSQL**: 12+ (advanced SQL function features)
- **ActiveJob**: Any backend (Sidekiq, DelayedJob, etc.)

### Architectural Constraints
- **Rails Engine**: Must integrate cleanly with host applications
- **Database Agnostic**: Core logic works with any ActiveRecord adapter (PostgreSQL functions are optional optimization)
- **Thread Safety**: All components must be thread-safe for concurrent execution
- **Backward Compatibility**: API changes must maintain compatibility

## Tool Usage Patterns

### Testing Strategy
```ruby
# RSpec configuration
RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.include FactoryBot::Syntax::Methods
end

# Test categories
# - Unit tests: Individual component behavior
# - Integration tests: Component interaction
# - System tests: End-to-end workflow execution
```

### Factory Patterns
```ruby
# Task factories with traits
FactoryBot.create(:task, :api_integration_with_steps)
FactoryBot.create(:task, :complete, context: { cart_id: 123 })

# Complex workflow factories
FactoryBot.create(:linear_workflow_task)
FactoryBot.create(:diamond_workflow_task)
```

### SQL Function Development
- Functions versioned (v01, v02, etc.)
- Migrations create/update functions
- Manual updates required in development
- Performance testing with EXPLAIN ANALYZE

### State Machine Integration
```ruby
# Statesman configuration
class TaskStateMachine
  include Statesman::Machine

  state :pending, initial: true
  state :in_progress
  state :complete
  state :error

  transition from: :pending, to: [:in_progress, :cancelled]
  transition from: :in_progress, to: [:complete, :error]
end
```

## Development Workflows

### Feature Development
1. **Write failing tests** (TDD approach)
2. **Implement core logic** in lib/tasker/
3. **Update SQL functions** if needed
4. **Run full test suite** to ensure no regressions
5. **Update documentation** (YARD comments)

### SQL Function Updates
1. **Modify function files** in db/functions/
2. **Create migration** to update function
3. **Test locally** with manual execution
4. **Update both individual and batch versions**
5. **Verify performance** with large datasets

### Testing Workflow
```bash
# Run specific test categories
bundle exec rspec spec/lib/                    # Unit tests
bundle exec rspec spec/integration/            # Integration tests
bundle exec rspec spec/tasks/                  # System tests

# Run with specific formatters
bundle exec rspec --format documentation       # Detailed output
bundle exec rspec --format progress           # Concise output

# Debug specific failures
bundle exec rspec spec/path/to/failing_spec.rb:123
```

### Performance Testing
- **SQL EXPLAIN**: Analyze query performance
- **Benchmark**: Time-critical operations
- **Memory Profiling**: Detect memory leaks
- **Load Testing**: High-volume workflow scenarios

## Integration Patterns

### Host Application Integration
```ruby
# In host application's Gemfile
gem 'tasker-engine', '~> 1.0.5'          # Production

# Mount engine in routes
Rails.application.routes.draw do
  mount Tasker::Engine => '/tasker'
end
```

### ActiveJob Integration
```ruby
# Task execution via ActiveJob
class ProcessOrderJob < ApplicationJob
  def perform(order_id)
    task = Tasker::Task.create!(
      name: 'order_processing',
      context: { order_id: order_id }
    )

    handler = Tasker::HandlerFactory.instance.get('order_processing')
    handler.handle(task)
  end
end
```

### Event System Integration
```ruby
# Subscribe to workflow events
Tasker::Events.subscribe('task.completed') do |event|
  Rails.logger.info "Task #{event[:task_id]} completed"
  NotificationService.send_completion_email(event[:task_id])
end
