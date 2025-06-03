# Database Query Optimization Plan: Step Readiness Views & State Synchronization

## Overview

This document outlines a systematic approach to optimizing database query patterns in Tasker by focusing on **step readiness determination** and **state synchronization challenges**. As an orchestration system, Tasker's core value proposition is making complex workflows idempotent, retryable, observable, and easy to reason about - all while maintaining minimal framework overhead.

The fundamental challenge in any event-driven, state-dependent system is understanding **what has changed since the last time context was refreshed** from the source system. In-memory objects may not reflect current database state, creating a problem similar to (but not identical to) caching invalidation.

## 🎯 **PROJECT GOALS**

**Primary Objective**: Optimize step readiness determination and state synchronization to eliminate expensive query patterns while maintaining correctness of workflow execution decisions.

**Core Insight**: The heart of query complexity in Tasker is determining step **readiness** - whether steps are ready for execution based on parent completion, retry/backoff status, timing constraints, and dependency satisfaction.

**Success Criteria**:
- ✅ Single-query step readiness determination regardless of workflow complexity
- ✅ Database views as authoritative source for calculated state
- ✅ Efficient state synchronization patterns that trust fresh DB state
- ✅ Maintained correctness of readiness decisions under all conditions
- ✅ Framework overhead <100ms regardless of workflow complexity

## 🔍 **STEP 1: WORKFLOW UNDERSTANDING - STATE SYNCHRONIZATION FOCUS**

### **The Core Challenge: Step Readiness Determination**

Every workflow processing iteration must answer: **"Which steps are ready to execute now?"**

This requires checking:
1. **Dependency Satisfaction**: Are all parent steps complete?
2. **Retry State**: Is the step within retry limits?
3. **Backoff Timing**: Has enough time passed since last failure?
4. **Current State**: Is the step in a state that allows execution?
5. **Concurrent Limits**: Are we within concurrency constraints?

### **Current Query Hotspots (Readiness-Focused Analysis)**

**❌ Problem Pattern**: Each readiness check requires fresh DB state
```ruby
# This pattern repeats throughout the codebase:
sequence.steps.each do |step|
  # 1. Refresh step state from DB
  fresh_step = step.persisted? ? Tasker::WorkflowStep.find(step.workflow_step_id) : step

  # 2. Check parent completion (more queries)
  parents_complete = fresh_step.parents.all?(&:complete?)

  # 3. Check retry/backoff state (more queries)
  within_retry_limits = fresh_step.attempts < fresh_step.retry_limit
  backoff_satisfied = check_backoff_timing(fresh_step)

  # 4. Determine readiness (requires state machine query)
  ready = fresh_step.pending? && parents_complete && within_retry_limits && backoff_satisfied
end
```

**🎯 Solution Strategy**: Replace individual readiness checks with database views that calculate readiness efficiently.

## 🏗️ **STEP 2: SCENIC VIEWS ARCHITECTURE**

### **2.1: Core Readiness Views**

#### **View 1: `step_readiness_status`**
**Purpose**: Single source of truth for step execution readiness

```sql
-- db/views/step_readiness_status_v01.sql
SELECT
  ws.workflow_step_id,
  ws.task_id,
  ws.named_step_id,
  ws.name,

  -- Current State Information
  COALESCE(current_state.to_state, 'pending') as current_state,

  -- Dependency Analysis
  CASE
    WHEN dep_check.total_parents = 0 THEN true
    WHEN dep_check.completed_parents = dep_check.total_parents THEN true
    ELSE false
  END as dependencies_satisfied,

  -- Retry & Backoff Analysis
  CASE
    WHEN ws.attempts >= COALESCE(ws.retry_limit, 3) THEN false
    WHEN last_failure.created_at IS NULL THEN true
    WHEN last_failure.created_at + (
      power(2, ws.attempts) * interval '1 second' * COALESCE(ws.base_retry_delay, 1)
    ) <= NOW() THEN true
    ELSE false
  END as retry_eligible,

  -- Final Readiness Calculation
  CASE
    WHEN COALESCE(current_state.to_state, 'pending') IN ('pending', 'failed')
    AND (dep_check.total_parents = 0 OR dep_check.completed_parents = dep_check.total_parents)
    AND (ws.attempts < COALESCE(ws.retry_limit, 3))
    AND (last_failure.created_at IS NULL OR
         last_failure.created_at + (power(2, ws.attempts) * interval '1 second' * COALESCE(ws.base_retry_delay, 1)) <= NOW())
    THEN true
    ELSE false
  END as ready_for_execution,

  -- Timing Information
  last_failure.created_at as last_failure_at,
  CASE
    WHEN last_failure.created_at IS NOT NULL THEN
      last_failure.created_at + (power(2, ws.attempts) * interval '1 second' * COALESCE(ws.base_retry_delay, 1))
    ELSE NULL
  END as next_retry_at

FROM tasker_workflow_steps ws

-- Current State Subquery
LEFT JOIN (
  SELECT DISTINCT ON (workflow_step_id)
    workflow_step_id, to_state
  FROM tasker_workflow_step_transitions
  ORDER BY workflow_step_id, created_at DESC
) current_state ON current_state.workflow_step_id = ws.workflow_step_id

-- Dependency Satisfaction Subquery
LEFT JOIN (
  SELECT
    child.workflow_step_id,
    COUNT(*) as total_parents,
    COUNT(CASE WHEN parent_state.to_state = 'complete' THEN 1 END) as completed_parents
  FROM tasker_workflow_step_dependencies dep
  JOIN tasker_workflow_steps child ON child.workflow_step_id = dep.workflow_step_id
  JOIN tasker_workflow_steps parent ON parent.workflow_step_id = dep.parent_workflow_step_id
  LEFT JOIN (
    SELECT DISTINCT ON (workflow_step_id)
      workflow_step_id, to_state
    FROM tasker_workflow_step_transitions
    ORDER BY workflow_step_id, created_at DESC
  ) parent_state ON parent_state.workflow_step_id = parent.workflow_step_id
  GROUP BY child.workflow_step_id
) dep_check ON dep_check.workflow_step_id = ws.workflow_step_id

-- Last Failure Information
LEFT JOIN (
  SELECT DISTINCT ON (workflow_step_id)
    workflow_step_id, created_at
  FROM tasker_workflow_step_transitions
  WHERE to_state = 'failed'
  ORDER BY workflow_step_id, created_at DESC
) last_failure ON last_failure.workflow_step_id = ws.workflow_step_id;
```

#### **View 2: `task_execution_context`**
**Purpose**: Comprehensive task state with workflow statistics

```sql
-- db/views/task_execution_context_v01.sql
SELECT
  t.task_id,
  t.named_task_id,
  t.status,

  -- Step Statistics
  step_stats.total_steps,
  step_stats.pending_steps,
  step_stats.in_progress_steps,
  step_stats.completed_steps,
  step_stats.failed_steps,
  step_stats.ready_steps,

  -- Execution State
  CASE
    WHEN step_stats.ready_steps > 0 THEN 'has_ready_steps'
    WHEN step_stats.in_progress_steps > 0 THEN 'processing'
    WHEN step_stats.failed_steps > 0 AND step_stats.ready_steps = 0 THEN 'blocked_by_failures'
    WHEN step_stats.completed_steps = step_stats.total_steps THEN 'all_complete'
    ELSE 'waiting_for_dependencies'
  END as execution_status,

  -- Next Action Recommendations
  CASE
    WHEN step_stats.ready_steps > 0 THEN 'execute_ready_steps'
    WHEN step_stats.in_progress_steps > 0 THEN 'wait_for_completion'
    WHEN step_stats.failed_steps > 0 AND step_stats.ready_steps = 0 THEN 'handle_failures'
    WHEN step_stats.completed_steps = step_stats.total_steps THEN 'finalize_task'
    ELSE 'wait_for_dependencies'
  END as recommended_action

FROM tasker_tasks t

JOIN (
  SELECT
    ws.task_id,
    COUNT(*) as total_steps,
    COUNT(CASE WHEN srs.current_state = 'pending' THEN 1 END) as pending_steps,
    COUNT(CASE WHEN srs.current_state = 'in_progress' THEN 1 END) as in_progress_steps,
    COUNT(CASE WHEN srs.current_state = 'complete' THEN 1 END) as completed_steps,
    COUNT(CASE WHEN srs.current_state = 'failed' THEN 1 END) as failed_steps,
    COUNT(CASE WHEN srs.ready_for_execution = true THEN 1 END) as ready_steps
  FROM tasker_workflow_steps ws
  JOIN step_readiness_status srs ON srs.workflow_step_id = ws.workflow_step_id
  GROUP BY ws.task_id
) step_stats ON step_stats.task_id = t.task_id;
```

### **2.2: ActiveRecord Models for Views**

```ruby
# app/models/tasker/step_readiness_status.rb
module Tasker
  class StepReadinessStatus < ApplicationRecord
    self.table_name = 'step_readiness_status'
    self.primary_key = 'workflow_step_id'

    # Read-only model backed by database view
    def readonly?
      true
    end

    # Associations to actual models for additional data
    belongs_to :workflow_step, foreign_key: 'workflow_step_id'
    belongs_to :task, foreign_key: 'task_id'

    # Scopes for common queries
    scope :ready, -> { where(ready_for_execution: true) }
    scope :blocked_by_dependencies, -> { where(dependencies_satisfied: false) }
    scope :blocked_by_retry, -> { where(retry_eligible: false) }
    scope :for_task, ->(task_id) { where(task_id: task_id) }

    # Helper methods
    def can_execute_now?
      ready_for_execution
    end

    def blocking_reason
      return nil if ready_for_execution
      return 'dependencies_not_satisfied' unless dependencies_satisfied
      return 'retry_not_eligible' unless retry_eligible
      return 'invalid_state' unless %w[pending failed].include?(current_state)
      'unknown'
    end

    def time_until_ready
      return 0 if ready_for_execution
      return nil unless next_retry_at
      [(next_retry_at - Time.current).to_i, 0].max
    end
  end
end

# app/models/tasker/task_execution_context.rb
module Tasker
  class TaskExecutionContext < ApplicationRecord
    self.table_name = 'task_execution_context'
    self.primary_key = 'task_id'

    def readonly?
      true
    end

    belongs_to :task, foreign_key: 'task_id'

    scope :with_ready_steps, -> { where('ready_steps > 0') }
    scope :blocked, -> { where(execution_status: 'blocked_by_failures') }
    scope :complete, -> { where(execution_status: 'all_complete') }

    def has_work_to_do?
      %w[has_ready_steps processing].include?(execution_status)
    end

    def is_blocked?
      execution_status == 'blocked_by_failures'
    end

    def is_complete?
      execution_status == 'all_complete'
    end
  end
end
```

## 🔧 **STEP 3: REFACTORED QUERY PATTERNS**

### **3.1: Optimized Viable Step Discovery**

**Before (N+1 Pattern)**:
```ruby
def self.get_viable_steps(task, sequence)
  sequence.steps.each do |step|
    fresh_step = step.persisted? ? Tasker::WorkflowStep.find(step.workflow_step_id) : step
    # ... complex readiness logic with more queries
  end
end
```

**After (View-Based Pattern)**:
```ruby
def self.get_viable_steps(task, sequence)
  # Single query to get all readiness information
  step_ids = sequence.steps.map(&:workflow_step_id)
  ready_steps = StepReadinessStatus.ready.where(workflow_step_id: step_ids)

  # Convert view results back to WorkflowStep objects if needed
  WorkflowStep.where(workflow_step_id: ready_steps.pluck(:workflow_step_id))
end
```

### **3.2: Optimized Task Processing Loop**

**Before (Multiple Query Pattern)**:
```ruby
def handle
  loop do
    task.reload
    sequence = get_sequence(task)
    viable_steps = find_viable_steps(task, sequence)
    break if viable_steps.empty?
    # ... process steps
    break if blocked_by_errors?(task, sequence, processed_steps)
  end
end
```

**After (View-Based Pattern)**:
```ruby
def handle
  loop do
    # Single query to get complete task execution context
    context = TaskExecutionContext.find(task.task_id)

    case context.recommended_action
    when 'execute_ready_steps'
      ready_steps = StepReadinessStatus.ready.for_task(task.task_id)
      process_ready_steps(ready_steps)
    when 'wait_for_completion'
      # Check again after brief pause
      sleep(0.1)
      next
    when 'handle_failures', 'finalize_task'
      break
    else
      break  # No work to do
    end
  end
end
```

### **3.3: Event Payload Optimization**

**Before (Association Loading)**:
```ruby
def build_step_payload(step, event_type:, additional_context: {})
  {
    step_dependencies: step.parents.map(&:name),  # N+1 query
    # ... other payload data
  }
end
```

**After (View-Based Payload)**:
```ruby
def build_step_payload(step, event_type:, additional_context: {})
  # Use view for efficient dependency information
  readiness_info = StepReadinessStatus.find(step.workflow_step_id)

  {
    step_dependencies: step.parents.includes(:named_step).map { |p| p.named_step.name },
    dependencies_satisfied: readiness_info.dependencies_satisfied,
    retry_eligible: readiness_info.retry_eligible,
    blocking_reason: readiness_info.blocking_reason,
    # ... other payload data
  }
end
```

## 🏗️ **STEP 4: IMPLEMENTATION PHASES**

### **Phase 1: Core Views & Models (Week 1)**

**Deliverables**:
- [ ] Create `step_readiness_status` view with comprehensive readiness logic
- [ ] Create `task_execution_context` view with workflow statistics
- [ ] Implement corresponding ActiveRecord models
- [ ] Add database indexes to support view performance
- [ ] Create migration for view deployment

**Technical Tasks**:
```bash
# Generate Scenic views
rails generate scenic:model step_readiness_status
rails generate scenic:model task_execution_context

# Create supporting indexes
rails generate migration AddIndexesForStepReadinessViews
```

### **Phase 2: Query Pattern Migration (Week 1-2)**

**Deliverables**:
- [ ] Refactor `WorkflowStep.get_viable_steps` to use views
- [ ] Update `TaskHandler.handle` processing loop to use `TaskExecutionContext`
- [ ] Migrate `all_parents_complete?` and related methods to view-based patterns
- [ ] Update `EventPayloadBuilder` to use readiness views

**Performance Validation**:
- [ ] Create benchmark tests comparing old vs. new query patterns
- [ ] Verify query count reduction (target: <10 queries per workflow iteration)
- [ ] Validate correctness of readiness determinations

### **Phase 3: Advanced State Synchronization (Week 2-3)**

**Deliverables**:
- [ ] Implement materialized views for expensive calculations (if needed)
- [ ] Add view refresh strategies for high-frequency updates
- [ ] Create "state synchronization points" where views are authoritative
- [ ] Implement cache invalidation patterns for in-memory objects

**Advanced Features**:
```ruby
# Materialized view for complex workflow statistics (if needed)
rails generate scenic:view workflow_performance_stats --materialized

# Refresh strategy for materialized views
class WorkflowPerformanceStats < ApplicationRecord
  def self.refresh_if_stale
    return unless last_refresh_older_than?(5.minutes)
    Scenic.database.refresh_materialized_view(:workflow_performance_stats, concurrently: true)
  end
end
```

### **Phase 4: Performance Monitoring & Optimization (Week 3-4)**

**Deliverables**:
- [ ] Add view performance monitoring
- [ ] Create automated performance regression tests
- [ ] Implement query result caching where appropriate
- [ ] Document view-based optimization patterns

**Monitoring Implementation**:
```ruby
# Add view performance monitoring
class StepReadinessStatus < ApplicationRecord
  around_action :monitor_view_performance

  private

  def monitor_view_performance
    start_time = Time.current
    result = yield
    duration = Time.current - start_time

    Rails.logger.info "StepReadinessStatus query: #{duration}ms"
    Tasker::Instrumentation.record_metric("view.step_readiness.duration", duration)

    result
  end
end
```

## 📊 **SUCCESS METRICS & VALIDATION**

### **Quantitative Goals**

1. **Query Reduction**:
   - **Before**: 50+ queries per workflow processing iteration
   - **Target**: <10 queries per iteration regardless of complexity
   - **Measurement**: ActiveRecord query logging during workflow processing

2. **Response Time Improvement**:
   - **Before**: Unmeasured (likely >500ms for complex workflows)
   - **Target**: <100ms framework overhead per iteration
   - **Measurement**: Benchmark tests with varying workflow complexity

3. **Memory Efficiency**:
   - **Target**: Linear memory growth with workflow size
   - **Measurement**: Memory profiling during processing of large workflows

### **Correctness Validation**

1. **Readiness Accuracy**:
   - View-based readiness must match complex in-memory calculations
   - Comprehensive test suite comparing old vs. new readiness logic
   - Edge case testing for retry timing, dependency cycles, concurrent execution

2. **State Synchronization**:
   - View data must reflect latest database state
   - Test scenarios with concurrent modifications
   - Validate that stale in-memory state doesn't affect decisions

### **Performance Test Suite**

```ruby
# spec/performance/view_optimization_spec.rb
RSpec.describe "View-Based Query Optimization" do
  context "step readiness determination" do
    it "uses constant queries regardless of workflow complexity" do
      # Test with varying complexity
      [5, 20, 50, 100].each do |step_count|
        task = create_complex_workflow(step_count: step_count)

        query_count = count_queries do
          StepReadinessStatus.ready.for_task(task.task_id).to_a
        end

        expect(query_count).to eq(1),
          "Expected 1 query for #{step_count} steps, got #{query_count}"
      end
    end
  end

  context "task execution context" do
    it "provides complete workflow state in single query" do
      task = create_complex_workflow(step_count: 25, dependency_depth: 5)

      query_count = count_queries do
        context = TaskExecutionContext.find(task.task_id)

        # Verify all necessary data is available
        expect(context.total_steps).to eq(25)
        expect(context.execution_status).to be_present
        expect(context.recommended_action).to be_present
      end

      expect(query_count).to eq(1)
    end
  end
end
```

## 🔄 **STATE SYNCHRONIZATION STRATEGY**

### **Trust-But-Verify Pattern**

**Core Principle**: Views provide authoritative state, in-memory objects are for convenience

```ruby
class WorkflowStep < ApplicationRecord
  # Traditional association methods for convenience
  has_many :parents, through: :incoming_dependencies

  # View-backed methods for authoritative state
  def current_readiness_status
    @readiness_status ||= StepReadinessStatus.find(workflow_step_id)
  end

  def ready_for_execution?
    current_readiness_status.ready_for_execution
  end

  def refresh_readiness_status!
    @readiness_status = nil
    current_readiness_status
  end

  # Deprecate methods that require fresh DB state
  def all_parents_complete?
    Rails.logger.warn "DEPRECATED: Use ready_for_execution? instead"
    current_readiness_status.dependencies_satisfied
  end
end
```

### **View Refresh Strategies**

**For Regular Views**: Always fresh (no caching needed)
```ruby
# Views calculate fresh state on every query
ready_steps = StepReadinessStatus.ready.for_task(task_id)
```

**For Materialized Views**: Refresh when stale
```ruby
# Refresh materialized views when underlying data changes
class WorkflowStepTransition < ApplicationRecord
  after_create :refresh_dependent_materialized_views

  private

  def refresh_dependent_materialized_views
    # Only if using materialized views for expensive calculations
    MaterializedWorkflowStats.refresh_if_stale
  end
end
```

## 🔗 **INTEGRATION WITH EXISTING ARCHITECTURE**

### **Backwards Compatibility**

- Existing `WorkflowStep` and `Task` methods continue to work
- Add deprecation warnings for inefficient patterns
- Gradual migration path from association-based to view-based queries

### **Event System Integration**

- Views provide optimized data for event payload building
- TelemetrySubscriber gets richer context from view data
- OpenTelemetry spans include view-based performance metrics

### **Testing Strategy**

- Comprehensive test coverage comparing old vs. new query patterns
- Performance regression tests with view-based optimizations
- Edge case testing for readiness logic accuracy

---

**Document Status**: ACTIVE IMPLEMENTATION PLAN
**Last Updated**: December 2024
**Next Review**: After Phase 1 completion
**Owner**: Development Team
**Dependencies**: Scenic gem installed and configured
