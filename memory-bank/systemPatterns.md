# System Patterns

## Architecture Overview

### Core Components
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Task Handler  │    │  Orchestration  │    │  SQL Functions  │
│                 │    │   Coordinator   │    │                 │
│ - Step Templates│────│ - Step Discovery│────│ - Step Readiness│
│ - Handler Logic │    │ - Step Executor │    │ - Task Context  │
│ - Dependencies  │    │ - Task Finalizer│    │ - Batch Queries │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │              ┌─────────────────┐              │
         │              │  State Machine  │              │
         └──────────────│                 │──────────────┘
                        │ - Task States   │
                        │ - Step States   │
                        │ - Transitions   │
                        └─────────────────┘
```

## Key Design Patterns

### 1. Strategy Pattern - Orchestration Components
**Problem**: Different execution contexts (production vs testing) need different behaviors
**Solution**: Pluggable strategies for coordination and reenqueuing

```ruby
class WorkflowCoordinator
  def initialize(reenqueuer_strategy: nil)
    @reenqueuer_strategy = reenqueuer_strategy || default_reenqueuer_strategy
  end
end

# Production: Uses ActiveJob
# Testing: Uses TestReenqueuer for synchronous execution
```

### 2. Function-Based Performance Pattern
**Problem**: Step readiness calculation was too slow with ActiveRecord queries
**Solution**: PostgreSQL functions for high-performance batch operations

```sql
-- Single function call replaces dozens of ActiveRecord queries
SELECT * FROM get_step_readiness_status(task_id, step_ids);
```

### 3. State Machine Pattern
**Problem**: Complex state transitions with validation and history
**Solution**: Dedicated state machine with transition tracking

```ruby
# Both tasks and steps use consistent state machine pattern
task.state_machine.transition_to('in_progress')
step.state_machine.transition_to('complete')
```

### 4. Event-Driven Architecture
**Problem**: Need observability and loose coupling between components
**Solution**: Publish/subscribe event system

```ruby
publish_step_completed(step, execution_duration: duration)
publish_task_finalization_started(task, context: context)
```

## Critical Implementation Paths

### Step Readiness Calculation
**Most Performance-Critical Path**
1. `WorkflowStep.get_viable_steps()` calls SQL function
2. `get_step_readiness_status()` evaluates:
   - Current step state
   - Dependency satisfaction
   - Retry eligibility (with backoff logic)
   - Processing flags
3. Returns only steps ready for immediate execution

**Key Optimization**: Single SQL function call replaces N+1 query patterns

### Task Execution Loop
**Core Orchestration Logic**
```ruby
loop do
  viable_steps = find_viable_steps(task, sequence)
  break if viable_steps.empty?

  processed_steps = execute_steps(viable_steps)
  break if blocked_by_errors?(task, processed_steps)
end

finalize_task(task, all_processed_steps)
```

### Retry Logic Implementation
**Complex Business Logic**
1. **Exponential Backoff**: `2^attempts * base_interval` (max 30 seconds)
2. **Retry Limits**: Configurable per step template
3. **Backoff Override**: Manual backoff periods for specific scenarios
4. **State Coordination**: Failed steps marked as `processed=false` for retry eligibility

## Component Relationships

### Task Handler → Orchestration
- Task handlers define step templates and dependencies
- Orchestration components execute the defined workflows
- Clean separation of business logic from execution logic

### SQL Functions → ActiveRecord Models
- SQL functions provide raw performance data
- ActiveRecord models wrap functions with Ruby interfaces
- Caching layer prevents redundant function calls

### State Machine → Database
- State machines manage transitions and validation
- Database stores transition history for audit trails
- Most recent transitions flagged for performance

### Event System → Observability
- All major workflow events published to event bus
- Telemetry subscribers collect metrics and logs
- Loose coupling allows adding new observers without code changes

## Error Handling Patterns

### Graceful Degradation
- SQL function failures fall back to ActiveRecord queries
- Missing dependencies cause workflow pause, not failure
- Partial step completion preserved across retries

### Idempotency Guarantees
- Steps can be safely re-executed without side effects
- Database transactions ensure atomic state changes
- Unique constraints prevent duplicate step creation

### Recovery Mechanisms
- Failed steps can be manually reset for retry
- Workflow state can be reconstructed from transition history
- Test infrastructure provides backoff bypass for rapid testing

## Performance Optimizations

### Database Level
- Composite indexes on (task_id, most_recent) for fast state lookups
- Function-based step readiness calculation
- Batch operations for multi-task scenarios

### Application Level
- Connection pooling for concurrent step execution
- Memory-efficient step processing with limited concurrency
- Cached step readiness status to prevent redundant calculations

### Testing Level
- Synchronous test coordinators bypass ActiveJob overhead
- Configurable failure handlers for deterministic test scenarios
- Backoff bypass mechanisms for rapid test execution
