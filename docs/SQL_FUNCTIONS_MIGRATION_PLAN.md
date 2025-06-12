# SQL Functions Migration Plan

## Overview
Replace database views with SQL functions to achieve production-scale performance by leveraging targeted ID-based queries with existing indexes.

## Current Performance Issues
- Views scan entire tables even with "active" filtering
- Query times of ~0.98s for 10K records won't scale to millions
- Complex view logic with subqueries creates performance bottlenecks
- Active/complete distinction adds unnecessary complexity

## Solution: SQL Functions with ID Parameters
SQL functions with pre-compiled execution plans + targeted ID queries = O(log n) performance instead of O(n).

## Technical Architecture

### Core Functions
1. **`get_step_readiness_status(step_ids INTEGER[])`**
   - Input: Array of workflow_step_ids
   - Output: Table with readiness data for each step
   - Uses existing indexes on workflow_step_id for fast lookups

2. **`get_task_execution_context(task_id INTEGER)`**
   - Input: Single task_id
   - Output: Single row with aggregated task context
   - Internally calls `get_step_readiness_status()` with task's step IDs

### Function Signatures

```sql
-- Step Readiness Function
CREATE OR REPLACE FUNCTION get_step_readiness_status(step_ids INTEGER[])
RETURNS TABLE(
  workflow_step_id INTEGER,
  task_id INTEGER,
  named_step_id INTEGER,
  name TEXT,
  current_state TEXT,
  dependencies_satisfied BOOLEAN,
  retry_eligible BOOLEAN,
  ready_for_execution BOOLEAN,
  last_failure_at TIMESTAMP,
  next_retry_at TIMESTAMP,
  total_parents INTEGER,
  completed_parents INTEGER,
  attempts INTEGER,
  retry_limit INTEGER,
  backoff_request_seconds INTEGER,
  last_attempted_at TIMESTAMP
) LANGUAGE plpgsql STABLE;

-- Task Execution Context Function
CREATE OR REPLACE FUNCTION get_task_execution_context(task_id INTEGER)
RETURNS TABLE(
  task_id INTEGER,
  named_task_id INTEGER,
  status TEXT,
  total_steps INTEGER,
  pending_steps INTEGER,
  in_progress_steps INTEGER,
  completed_steps INTEGER,
  failed_steps INTEGER,
  ready_steps INTEGER,
  execution_status TEXT,
  recommended_action TEXT,
  completion_percentage DECIMAL,
  health_status TEXT
) LANGUAGE plpgsql STABLE;
```

## Implementation Plan

### Phase 1: Create SQL Functions
**Files to Create:**
- `db/migrate/20241212000001_create_step_readiness_function.rb`
- `db/migrate/20241212000002_create_task_execution_context_function.rb`
- `db/migrate/20241212000003_create_batch_task_execution_context_function.rb`
- `db/functions/get_step_readiness_status_v01.sql`
- `db/functions/get_task_execution_context_v01.sql`
- `db/functions/get_task_execution_contexts_batch_v01.sql`

**Migration Strategy:**
- Create `db/functions/` directory for SQL function files
- Use Rails migrations to execute function creation
- Functions will be versioned (v01) for future updates

### Phase 2: Ruby Integration Layer
**Files to Update:**
- `app/models/tasker/step_readiness_status.rb` - Convert to function-based model
- `app/models/tasker/task_execution_context.rb` - Convert to function-based model
- `lib/tasker/views/` - Create function wrapper utilities

**Ruby Interface Design:**
```ruby
# Maintain existing interface
class StepReadinessStatus
  def self.for_steps(step_ids)
    connection.select_all(
      "SELECT * FROM get_step_readiness_status($1)",
      "StepReadinessStatus Load",
      [step_ids]
    ).map { |row| new(row) }
  end

  def self.ready_for_execution
    # Scope-like interface for compatibility
    ReadyStepsScope.new
  end
end

class TaskExecutionContext
  def self.find(task_id)
    result = connection.select_one(
      "SELECT * FROM get_task_execution_context($1)",
      "TaskExecutionContext Load",
      [task_id]
    )
    result ? new(result) : nil
  end
end
```

### Phase 3: Testing Strategy
**Function-Level Tests:**
- `spec/db/functions/step_readiness_status_spec.rb`
- `spec/db/functions/task_execution_context_spec.rb`
- Direct SQL function testing with various scenarios

**Integration Tests:**
- Existing integration tests will validate end-to-end functionality
- Performance benchmarks to verify improvement

### Phase 4: Migration & Cleanup
**Remove Old Infrastructure:**
- Delete view files: `db/views/tasker_*_v01.sql`
- Remove view migrations (keep index migrations)
- Delete active view models: `ActiveStepReadinessStatus`, `ActiveTaskExecutionContext`
- Remove view router: `lib/tasker/views/smart_view_router.rb`

**Keep Existing Indexes:**
All current indexes remain valuable for function performance:
- `tasker_workflow_steps(workflow_step_id)` - Primary key
- `tasker_workflow_steps(task_id)` - Task lookup
- `tasker_workflow_step_transitions(workflow_step_id, most_recent)` - State lookup
- `tasker_workflow_step_edges(to_step_id, from_step_id)` - Dependency lookup
- `tasker_tasks(task_id)` - Task lookup

## Performance Benefits

### Before (Views)
- Full table scan of all workflow steps
- Complex subqueries and joins
- ~0.98s for 10K records
- O(n) complexity

### After (Functions)
- Index seeks on specific step/task IDs
- Pre-compiled execution plans
- Expected <10ms for any number of records
- O(log n) complexity

## Risk Mitigation

### Database Compatibility
- PostgreSQL functions are well-supported
- STABLE functions are cacheable and safe for read replicas
- No vendor lock-in (functions can be ported to other SQL databases)

### Rollback Strategy
- Keep view migrations temporarily during transition
- Feature flag to switch between views and functions
- Gradual rollout with performance monitoring

### Testing Coverage
- Comprehensive function unit tests
- All existing integration tests continue to pass
- Performance regression tests

## File Structure After Migration

```
db/
├── functions/
│   ├── get_step_readiness_status_v01.sql
│   └── get_task_execution_context_v01.sql
├── migrate/
│   ├── [existing index migrations - KEEP]
│   ├── 20241212000001_create_step_readiness_function.rb
│   └── 20241212000002_create_task_execution_context_function.rb
└── [remove db/views/ directory]

app/models/tasker/
├── step_readiness_status.rb [updated for functions]
├── task_execution_context.rb [updated for functions]
└── [remove active_* models]

spec/
├── db/functions/ [new function tests]
├── models/ [updated model tests]
└── integration/ [existing tests - should pass]
```

## Success Criteria
1. **Performance**: Query times <10ms for any dataset size
2. **Compatibility**: All existing tests pass without modification
3. **Maintainability**: Simpler codebase without view complexity
4. **Scalability**: Production-ready for millions of records

## Next Steps
1. Create first SQL function for step readiness status
2. Build Ruby wrapper maintaining existing interface
3. Add comprehensive function tests
4. Migrate task execution context function
5. Remove old view infrastructure

This approach eliminates the performance bottleneck while maintaining a clean, testable interface that scales to production workloads.
