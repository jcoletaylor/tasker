# Tasker Troubleshooting Guide

## Overview

This guide covers common issues and solutions you may encounter when developing with Tasker and deploying Tasker-based workflows to production. It's organized into development-time issues and deployment-time issues for easy navigation.

## Development Troubleshooting

### Task Handler Issues

#### "Task handler not found" or "NameError: uninitialized constant"

**Symptoms:**
```ruby
# Error when trying to create or execute tasks
NameError: uninitialized constant OrderProcess
# or
Tasker::TaskHandler::NotFoundError: Task handler 'order_process' not found
```

**Common Causes & Solutions:**

1. **File naming mismatch**
   ```bash
   # Ensure file name matches class name
   app/tasks/order_process.rb  # File name should be snake_case
   class OrderProcess          # Class name should be CamelCase
   ```

2. **YAML configuration mismatch**
   ```yaml
   # config/tasker/tasks/order_process.yaml
   name: order_process                    # Must match file name
   task_handler_class: OrderProcess       # Must match class name exactly
   ```

3. **Module namespace issues**
   ```ruby
   # If using module namespaces, ensure they're consistent
   # YAML: module_namespace: ECommerce
   # File: app/tasks/e_commerce/order_process.rb
   module ECommerce
     class OrderProcess < Tasker::TaskHandler::Base
   ```

4. **Rails autoloading not picking up changes**
   ```bash
   # Restart Rails server to reload task handlers
   bundle exec rails server

   # Or in development, force reload
   Rails.application.reloader.reload!
   ```

#### "Step handler not found" or Step execution failures

**Symptoms:**
```ruby
# Step fails to execute or shows class loading errors
LoadError: unable to autoload constant WelcomeUser::StepHandler::ValidateUserHandler
```

**Solutions:**

1. **Check file structure and naming**
   ```bash
   # Correct structure
   app/tasks/welcome_user/step_handler/validate_user_handler.rb

   # Class should be properly namespaced
   module WelcomeUser
     module StepHandler
       class ValidateUserHandler < Tasker::StepHandler::Base
   ```

2. **Verify YAML step configuration**
   ```yaml
   step_templates:
     - name: validate_user
       handler_class: WelcomeUser::StepHandler::ValidateUserHandler  # Full namespace
   ```

3. **Check inheritance**
   ```ruby
   # Step handlers must inherit from appropriate base class
   class MyStepHandler < Tasker::StepHandler::Base        # For general steps
   class MyApiHandler < Tasker::StepHandler::Api          # For API steps
   ```

### Step Dependency Issues

#### Steps not executing in expected order

**Symptoms:**
- Steps run simultaneously when they should be sequential
- Steps wait indefinitely for dependencies
- Circular dependency errors

**Diagnosis & Solutions:**

1. **Check dependency configuration**
   ```yaml
   # Correct single dependency
   - name: step_two
     depends_on_step: step_one

   # Correct multiple dependencies
   - name: step_three
     depends_on_steps:
       - step_one
       - step_two
   ```

2. **Verify step names match exactly**
   ```yaml
   # Names must match exactly (case-sensitive)
   - name: validate_order      # Step name
   - name: process_payment
     depends_on_step: validate_order  # Must match exactly
   ```

3. **Check for circular dependencies**
   ```ruby
   # In Rails console, use the new dependency_graph method
   handler = Tasker::HandlerFactory.instance.get('your_task')
   graph = handler.dependency_graph

   # Check for cycles
   if graph[:cycles].any?
     puts "Circular dependencies detected:"
     graph[:cycles].each do |cycle|
       puts "  Cycle: #{cycle.join(' -> ')}"
     end
   else
     puts "No circular dependencies found"
   end

   # Show topology and dependency structure
   puts "\nExecution order: #{graph[:topology].join(' -> ')}"
   puts "Root steps (no dependencies): #{graph[:roots].join(', ')}"
   puts "Leaf steps (no dependents): #{graph[:leaves].join(', ')}"
   puts "Max parallel branches: #{graph[:summary][:parallel_branches]}"
   ```

4. **Debug dependency resolution**
   ```ruby
   # In Rails console, use runtime dependency analysis
   task = Tasker::Task.find(your_task_id)
   graph = task.dependency_graph

   # Overall task status
   puts "Task Status: #{graph[:summary][:task_state]}"
   puts "Completion: #{graph[:summary][:completion_percentage]}%"
   puts "Ready steps: #{graph[:ready_steps].join(', ')}"
   puts "Blocked steps: #{graph[:blocked_steps].join(', ')}"

   # Check for error chains
   if graph[:error_chains].any?
     puts "\nError Impact Analysis:"
     graph[:error_chains].each do |chain|
       puts "  Error step '#{chain[:root_error]}' blocking #{chain[:impact_count]} steps:"
       puts "    Blocked: #{chain[:blocked_steps].join(', ')}"
     end
   end

   # Detailed step analysis
   puts "\nDetailed Step Status:"
   graph[:nodes].each do |node|
     puts "#{node[:name]}: #{node[:state]} (#{node[:attempts]}/#{node[:retry_limit]} attempts)"
     puts "  Dependencies: #{node[:dependencies].join(', ')}" if node[:dependencies].any?
     puts "  Ready: #{node[:ready_for_execution]}"
   end
   ```

#### Diamond pattern dependency issues

**Problem:** Steps with multiple dependency paths not executing correctly

**Solution:**
```yaml
# Correct diamond pattern
- name: start_step          # No dependencies
- name: branch_a
  depends_on_step: start_step
- name: branch_b
  depends_on_step: start_step
- name: merge_step
  depends_on_steps:         # Waits for BOTH branches
    - branch_a
    - branch_b
```

### Step Implementation Issues

#### Steps marked as failed when they should succeed

**Symptoms:**
- Step completes successfully but shows as "error" state
- Expected return values not stored in step.results

**Common Causes & Solutions:**

1. **Exception handling masking success**
   ```ruby
   # WRONG - Catches exception but doesn't re-raise
   def process(task, sequence, step)
     begin
       result = perform_operation()
       { success: true, data: result }
     rescue => e
       # This makes the step appear successful to the framework
       { success: false, error: e.message }
     end
   end

   # CORRECT - Let exceptions propagate for framework handling
   def process(task, sequence, step)
     result = perform_operation()
     { success: true, data: result }
     # Framework automatically handles exceptions
   end

   # OR - Re-raise after logging custom error context
   def process(task, sequence, step)
     begin
       result = perform_operation()
       { success: true, data: result }
     rescue => e
       step.results = { error_context: "Additional details" }
       raise  # Re-raise so framework knows step failed
     end
   end
   ```

2. **Incorrect return values**
   ```ruby
   # WRONG - Not returning anything
   def process(task, sequence, step)
     step.results = { data: "some value" }
     # No return value - framework gets nil
   end

   # CORRECT - Return the results
   def process(task, sequence, step)
     { data: "some value" }
   end
   ```

#### Data not passed between steps correctly

**Symptoms:**
- Dependent steps can't access previous step results
- nil or empty results from previous steps

**Solutions:**

1. **Check step name references**
   ```ruby
   # Make sure step names match exactly
   previous_step = sequence.find_step_by_name('validate_user')  # Exact name
   user_data = previous_step.results['user_data']
   ```

2. **Verify previous step completed successfully**
   ```ruby
   def process(task, sequence, step)
     previous_step = sequence.find_step_by_name('previous_step')

     unless previous_step.current_state == 'complete'
       raise "Previous step not completed: #{previous_step.current_state}"
     end

     data = previous_step.results
   end
   ```

3. **Handle missing or malformed results**
   ```ruby
   def process(task, sequence, step)
     previous_step = sequence.find_step_by_name('fetch_data')

     unless previous_step&.results&.key?('required_field')
       raise "Previous step missing required data: #{previous_step&.results}"
     end

     required_data = previous_step.results['required_field']
   end
   ```

### Retry Logic Issues

#### Steps not retrying when they should

**Symptoms:**
- Failed steps go directly to error state instead of retrying
- Retry count not incrementing

**Solutions:**

1. **Check retry configuration**
   ```yaml
   # In YAML configuration
   - name: unreliable_step
     handler_class: MyHandler
     default_retryable: true        # Must be true for retries
     default_retry_limit: 3         # Set appropriate limit
   ```

2. **Verify exception types**
   ```ruby
   # Some exceptions may not be retryable by default
   def process(task, sequence, step)
     # For custom retry logic, use specific exceptions
     raise Tasker::RetryableError, "Temporary failure"  # Will retry
     # vs
     raise ArgumentError, "Invalid input"               # Won't retry
   end
   ```

3. **Check retry state in database**
   ```ruby
   # In Rails console
   step = Tasker::WorkflowStep.find(step_id)
   puts "Attempts: #{step.attempts}"
   puts "Retry limit: #{step.retry_limit}"
   puts "Retryable: #{step.retryable}"
   puts "State: #{step.current_state}"
   ```

#### Infinite retry loops

**Symptoms:**
- Steps retry indefinitely
- High CPU usage from constant retrying

**Solutions:**

1. **Check retry limits**
   ```yaml
   # Always set reasonable retry limits
   default_retry_limit: 3  # Don't use overly high values
   ```

2. **Implement exponential backoff awareness**
   ```ruby
   def process(task, sequence, step)
     # Check attempt count to adjust behavior
     if step.attempts > 2
       # Use more conservative approach on later attempts
       timeout = 30 * (step.attempts ** 2)  # Exponential timeout
     end
   end
   ```

### JSON Schema Validation Issues

#### Task requests failing validation

**Symptoms:**
```ruby
Tasker::Types::ValidationError: Invalid task context
```

**Solutions:**

1. **Check schema definition in YAML**
   ```yaml
   schema:
     type: object
     required:
       - user_id
       - order_id      # Make sure required fields are provided
     properties:
       user_id:
         type: integer
         minimum: 1    # Add appropriate constraints
       order_id:
         type: integer
   ```

2. **Validate context before task creation**
   ```ruby
   # Validate your context matches the schema
   context = { user_id: 123, order_id: 456 }

   task_request = Tasker::Types::TaskRequest.new(
     name: 'order_process',
     context: context
   )
   ```

## Deployment Troubleshooting

### Observability & Monitoring

#### Tasks stuck in pending state

**Symptoms:**
- Tasks created but never progress beyond 'pending'
- No step execution occurring

**Diagnosis Steps:**

1. **Check ActiveJob backend**
   ```bash
   # Ensure your job processor is running
   bundle exec sidekiq    # For Sidekiq
   # or check other ActiveJob backends
   ```

2. **Verify database connectivity**
   ```ruby
   # In Rails console
   Tasker::Task.connection.execute("SELECT 1")  # Should not raise error
   ```

3. **Check SQL function availability**
   ```ruby
   # Verify SQL functions are installed
   result = Tasker::Task.connection.execute(
     "SELECT get_task_execution_context_v01($1)", [task_id]
   )
   ```

4. **Monitor workflow coordination**
   ```ruby
   # Check if coordinator is processing tasks
   Tasker::Orchestration::Coordinator.new.coordinate_workflow_execution
   ```

#### No step execution events

**Symptoms:**
- Tasks and steps exist but no lifecycle events
- Missing telemetry data

**Solutions:**

1. **Verify event system configuration**
   ```ruby
   # Check if events are being published
   Tasker::Events.catalog.keys  # Should show available events
   ```

2. **Check event subscribers**
   ```ruby
   # Verify subscribers are registered
   Tasker::Events::Publisher.instance.subscribers
   ```

3. **Enable telemetry**
   ```ruby
   # config/initializers/tasker.rb
   Tasker.configuration do |config|
     config.telemetry do |tel|
       tel.enabled = true
       tel.service_name = 'your-app'
     end
   end
   ```

### Performance Issues

#### Slow step readiness calculations

**Symptoms:**
- Long delays between step completions and dependent step execution
- High database CPU usage

**Solutions:**

1. **Check SQL function performance**
   ```sql
   -- Monitor SQL function execution time
   EXPLAIN ANALYZE SELECT get_task_execution_context_v01(123);
   ```

2. **Verify database indexes**
   ```sql
   -- Ensure proper indexes exist
   \d tasker_workflow_steps;  -- Check indexes on workflow_steps table
   ```

3. **Monitor function call frequency**
   ```ruby
   # Check if functions are being called too frequently
   # Consider caching execution context for very active tasks
   ```

#### Memory leaks in long-running tasks

**Symptoms:**
- Memory usage grows over time
- Application becomes unresponsive

**Solutions:**

1. **Check step result sizes**
   ```ruby
   # Monitor step result sizes
   task.workflow_steps.each do |step|
     puts "#{step.name}: #{step.results.to_s.bytesize} bytes"
   end
   ```

2. **Implement result cleanup**
   ```ruby
   def process(task, sequence, step)
     result = large_operation()

     # Return only essential data
     {
       status: 'completed',
       record_count: result.size,
       # Don't return the entire large dataset
     }
   end
   ```

### Error Analysis

#### Analyzing step failure patterns

**Diagnostic Queries:**

```ruby
# Find frequently failing steps
failing_steps = Tasker::WorkflowStep
  .where(current_state: 'error')
  .group(:name)
  .count
  .sort_by { |_, count| -count }

# Analyze retry patterns
retry_analysis = Tasker::WorkflowStep
  .where('attempts > 1')
  .group(:name)
  .average(:attempts)

# Check error types
error_patterns = Tasker::WorkflowStep
  .where(current_state: 'error')
  .where.not(results: {})
  .map { |step| step.results['error'] }
  .compact
  .tally
```

#### Debugging specific task execution

```ruby
# Deep dive into specific task
task = Tasker::Task.find(task_id)

puts "Task: #{task.name} (#{task.state})"
puts "Created: #{task.created_at}"
puts "Context: #{task.context}"

task.workflow_steps.order(:created_at).each do |step|
  puts "\nStep: #{step.name}"
  puts "  State: #{step.current_state}"
  puts "  Attempts: #{step.attempts}/#{step.retry_limit}"
  puts "  Duration: #{step.execution_duration}s" if step.execution_duration
  puts "  Results: #{step.results}"

  if step.current_state == 'error'
    puts "  Error: #{step.results['error']}"
    puts "  Backtrace: #{step.results['backtrace']&.first(3)&.join("\n    ")}"
  end
end
```

### Logging & Observability Setup

#### Structured logging configuration

```ruby
# config/initializers/tasker.rb
Tasker.configuration do |config|
  config.telemetry do |tel|
    tel.enabled = true
    tel.service_name = 'your-application'
    tel.service_version = ENV['APP_VERSION'] || '1.0.0'
    tel.environment = Rails.env
  end
end
```

#### Custom event subscribers for monitoring

```ruby
# app/subscribers/monitoring_subscriber.rb
class MonitoringSubscriber < Tasker::Events::Subscribers::BaseSubscriber
  subscribe_to 'task.failed', 'step.failed', 'step.max_retries_reached'

  def handle_task_failed(event)
    task_id = safe_get(event, :task_id)
    error = safe_get(event, :error_message)

    # Send to your monitoring system
    Rails.logger.error("Task failed: #{task_id} - #{error}")
    AlertingService.notify_task_failure(task_id, error)
  end

  def handle_step_max_retries_reached(event)
    step_id = safe_get(event, :step_id)
    step_name = safe_get(event, :step_name)

    # Alert on retry exhaustion
    AlertingService.notify_step_retry_exhaustion(step_id, step_name)
  end
end
```

#### Production health checks

```ruby
# Check system health
def tasker_health_check
  checks = {
    database: database_connectivity_check,
    sql_functions: sql_functions_check,
    pending_tasks: pending_tasks_check,
    failed_tasks: failed_tasks_check
  }

  overall_health = checks.values.all? { |check| check[:status] == 'ok' }

  {
    status: overall_health ? 'healthy' : 'unhealthy',
    timestamp: Time.current.iso8601,
    checks: checks
  }
end

private

def database_connectivity_check
  Tasker::Task.connection.execute("SELECT 1")
  { status: 'ok', message: 'Database connected' }
rescue => e
  { status: 'error', message: e.message }
end

def sql_functions_check
  Tasker::Task.connection.execute("SELECT get_task_execution_context_v01(1)")
  { status: 'ok', message: 'SQL functions available' }
rescue => e
  { status: 'error', message: "SQL functions unavailable: #{e.message}" }
end

def pending_tasks_check
  count = Tasker::Task.where(state: 'pending').where('created_at < ?', 10.minutes.ago).count

  if count > 100
    { status: 'warning', message: "#{count} old pending tasks" }
  else
    { status: 'ok', message: "#{count} pending tasks" }
  end
end
```

## Diagnostic Tools & Commands

### Useful Rails Console Commands

```ruby
# Task status overview
def task_summary
  states = Tasker::Task.group(:state).count
  puts "Task States:"
  states.each { |state, count| puts "  #{state}: #{count}" }
end

# Step failure analysis
def step_failure_summary
  failures = Tasker::WorkflowStep
    .where(current_state: 'error')
    .group(:name)
    .count

  puts "Failed Steps:"
  failures.each { |name, count| puts "  #{name}: #{count}" }
end

# Recent task activity
def recent_activity(hours = 24)
  since = hours.hours.ago

  puts "Activity since #{since}:"
  puts "  Tasks created: #{Tasker::Task.where('created_at > ?', since).count}"
  puts "  Tasks completed: #{Tasker::Task.where('updated_at > ? AND state = ?', since, 'complete').count}"
  puts "  Tasks failed: #{Tasker::Task.where('updated_at > ? AND state = ?', since, 'error').count}"
end
```

### Database Queries for Analysis

```sql
-- Find long-running tasks
SELECT id, name, state, created_at, updated_at,
       EXTRACT(EPOCH FROM (NOW() - created_at))/3600 as hours_running
FROM tasker_tasks
WHERE state IN ('pending', 'processing')
  AND created_at < NOW() - INTERVAL '1 hour'
ORDER BY created_at;

-- Find steps with high retry rates
SELECT name,
       COUNT(*) as total_attempts,
       AVG(attempts) as avg_attempts,
       MAX(attempts) as max_attempts
FROM tasker_workflow_steps
WHERE attempts > 1
GROUP BY name
ORDER BY avg_attempts DESC;

-- Find tasks with many failed steps
SELECT t.id, t.name,
       COUNT(ws.id) as total_steps,
       COUNT(CASE WHEN ws.current_state = 'error' THEN 1 END) as failed_steps
FROM tasker_tasks t
JOIN tasker_workflow_steps ws ON ws.task_id = t.id
GROUP BY t.id, t.name
HAVING COUNT(CASE WHEN ws.current_state = 'error' THEN 1 END) > 0
ORDER BY failed_steps DESC;
```

## Getting Help

### Documentation Resources
- **[Quick Start Guide](QUICK_START.md)** - Basic workflow creation
- **[Developer Guide](DEVELOPER_GUIDE.md)** - Comprehensive implementation guide
- **[Event System](EVENT_SYSTEM.md)** - Observability and monitoring setup
- **[Authentication](AUTH.md)** - Security configuration
- **[System Overview](OVERVIEW.md)** - Architecture and advanced configuration

### Community & Support
- Check the GitHub issues for similar problems
- Review test examples in the `spec/` directory
- Examine example implementations in `spec/examples/`

### Debug Mode
Enable verbose logging for deeper insight:

```ruby
# config/environments/development.rb
Rails.application.configure do
  config.log_level = :debug

  # Enable SQL logging
  ActiveRecord::Base.logger = Logger.new(STDOUT) if defined?(Rails::Console)
end
```

Remember: Tasker is designed to be resilient and self-healing. Many transient issues will resolve themselves through the retry mechanism. Focus on patterns of persistent failures rather than isolated incidents.
