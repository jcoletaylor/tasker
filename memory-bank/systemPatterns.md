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

## Production Workflow Lifecycle

### Complete End-to-End Flow

```mermaid
graph TD
    A[Task Creation] --> B[Step Creation]
    B --> C[Initial State Setup]
    C --> D[TaskRunnerJob Enqueue]
    D --> E[Main Execution Loop]

    E --> F[SQL Function: Find Viable Steps]
    F --> G{Steps Available?}
    G -->|No| H[Task Finalization]
    G -->|Yes| I[StepExecutor: Execute Steps]

    I --> J{Step Success?}
    J -->|Success| K[processed=true, complete state]
    J -->|Failure| L[processed=false, error state, attempts++]

    K --> M{Blocked by Errors?}
    L --> M
    M -->|No| E
    M -->|Yes| H

    H --> N{Finalization Decision}
    N -->|ALL_COMPLETE| O[Task COMPLETE]
    N -->|BLOCKED_BY_FAILURES| P[Task ERROR]
    N -->|HAS_READY_STEPS| Q[TaskReenqueuer: Immediate]
    N -->|WAITING_FOR_DEPENDENCIES| R[TaskReenqueuer: Delayed]
    N -->|PROCESSING| S[TaskReenqueuer: Continue]

    Q --> D
    R --> D
    S --> D
```

### Phase-by-Phase Breakdown

#### Phase 1: Task Initialization
```ruby
# 1. Task Creation
task_request = Tasker::Types::TaskRequest.new(name: 'order_process', context: { order_id: 123 })

# 2. Task and Step Creation
handler = Tasker::HandlerFactory.instance.get('order_process')
task = handler.initialize_task!(task_request)

# 3. Initial State Setup
# Task: PENDING state
# Steps: PENDING state, processed = false, attempts = 0

# 4. Enqueue for Processing
Tasker::TaskRunnerJob.perform_later(task.task_id)
```

#### Phase 2: Main Execution Loop (WorkflowCoordinator)
```ruby
# CRITICAL: This is the core production logic
loop do
  task.reload
  sequence = get_sequence(task)

  # SQL Function Query - THE HEART OF THE SYSTEM
  viable_steps = find_viable_steps(task, sequence)
  break if viable_steps.empty?

  # Step Execution
  processed_steps = execute_steps(viable_steps)
  all_processed_steps.concat(processed_steps)

  # Error Check
  break if blocked_by_errors?(task)
end

# Finalization Decision
finalize_task(task, all_processed_steps)
```

#### Phase 3: Step Discovery & Retry Eligibility (SQL Function)
**The `get_step_readiness_status()` function is the authoritative source for step readiness:**

```sql
-- CRITICAL CONDITIONS for ready_for_execution = true:
CASE
  WHEN current_state IN ('pending', 'error')           -- Must be pending or failed
  AND (processed = false OR processed IS NULL)         -- Never re-execute processed steps
  AND dependencies_satisfied = true                    -- All parents complete
  AND attempts < retry_limit                           -- Haven't exhausted retries
  AND COALESCE(retryable, true) = true                 -- Step is retryable
  AND (in_process = false OR in_process IS NULL)       -- Not currently processing
  AND backoff_period_expired = true                    -- Exponential backoff satisfied
  THEN true
  ELSE false
END
```

**Key Retry Eligibility Logic:**
- **Exponential Backoff**: `2^attempts * 1 second` (max 30 seconds)
- **Manual Backoff Override**: `last_attempted_at + backoff_request_seconds`
- **Retry Limits**: Default 3 attempts, configurable per step
- **Retryability Flag**: `COALESCE(retryable, true)` - retryable by default

#### Phase 4: Step Execution (StepExecutor)
```ruby
# For each viable step:
def execute_single_step(task, sequence, step, task_handler)
  # 1. State Transition
  transition_to_in_progress(step)  # pending → in_progress

  # 2. Execute Handler
  step_handler = task_handler.get_step_handler(step)
  step_handler.handle(task, sequence, step)

  # 3. Success Path
  step.update!(processed: true)
  transition_to_complete(step)     # in_progress → complete

  # 4. Failure Path (if exception raised)
  step.update!(processed: false, attempts: attempts + 1)
  transition_to_error(step)        # in_progress → error
  store_error_data(step, exception)
end
```

#### Phase 5: Task Finalization & Reenqueuing
```ruby
# TaskFinalizer analyzes TaskExecutionContext
context = get_task_execution_context(task_id)

case context.execution_status
when 'all_complete'
  task.transition_to('complete')  # DONE
when 'blocked_by_failures'
  task.transition_to('error')     # DONE
when 'has_ready_steps'
  reenqueue_immediately(task)     # Continue processing
when 'waiting_for_dependencies'
  reenqueue_with_delay(task)      # Wait for backoff/dependencies
when 'processing'
  reenqueue_for_continuation(task) # Continue next iteration
end
```

#### Phase 6: Production Retry Mechanism
**Step-Level Retry Flow:**
1. **Step Fails**: `error` state, `processed = false`, `attempts++`
2. **Task Continues**: TaskFinalizer determines task should continue
3. **Reenqueuing**: `TaskReenqueuer` → `TaskRunnerJob.perform_later(task_id)`
4. **Next Loop**: SQL function finds failed step as `viable` (if retry eligible)
5. **Step Retry**: Same execution process, new attempt number

**CRITICAL**: This is **step-level retry via reenqueuing**, not task-level retry loops.

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

### 5. Reenqueuing-Based Retry Pattern
**Problem**: Need reliable step retry mechanism with backoff and limits
**Solution**: Failed steps become viable again through reenqueuing + SQL function

```ruby
# Production Flow:
failed_step  # error state, processed = false, attempts++
→ TaskFinalizer  # determines continuation needed
→ TaskReenqueuer  # TaskRunnerJob.perform_later(task_id)
→ New Execution Loop  # SQL function finds failed step as viable
→ Step Retry  # same execution process, new attempt
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

### Reenqueuing Decision Logic
**TaskFinalizer Business Rules**
- **All Complete**: Task done, no reenqueuing
- **Blocked by Failures**: Task failed, no reenqueuing
- **Has Ready Steps**: Immediate reenqueuing for step execution
- **Waiting**: Delayed reenqueuing based on earliest retry time
- **Processing**: Continuation reenqueuing for next iteration

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

### TaskReenqueuer → ActiveJob
- Reenqueuer translates continuation decisions into job enqueuing
- ActiveJob handles actual background processing
- Strategy pattern allows testing without actual job queuing

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

## Anti-Patterns and Common Mistakes

### ❌ Task-Level Retry Loops
**Wrong**: Implementing retry logic at the task level with manual loops
**Right**: Step-level retries through reenqueuing + SQL function eligibility

### ❌ Bypassing SQL Function Logic
**Wrong**: Using ActiveRecord queries to determine step readiness in tests
**Right**: Testing the actual SQL function behavior for retry eligibility

### ❌ Manual State Manipulation
**Wrong**: Directly updating step states without using state machine
**Right**: Using `safe_transition_to` for all state changes

### ❌ Ignoring `processed` Flag
**Wrong**: Re-executing steps that have `processed = true`
**Right**: Only executing steps with `processed = false`

### ❌ Incomplete Strategy Pattern
**Wrong**: Test strategies that don't replicate production behavior
**Right**: Test strategies that follow the same reenqueuing path as production
