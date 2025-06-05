# Database Query Optimization Plan: Step Readiness Views & State Synchronization

## 🎯 **CURRENT STATUS: INFRASTRUCTURE COMPLETE, MIGRATION IN PROGRESS**
*Updated: June 2025*

### **✅ COMPLETED: Phase 1 - Core Infrastructure (DONE)**

**Infrastructure Achievements:**
- ✅ **Scenic Views Created**: `tasker_step_readiness_statuses` and `tasker_task_execution_contexts` deployed and working
- ✅ **ActiveRecord Models**: `StepReadinessStatus` and `TaskExecutionContext` models implemented with associations
- ✅ **Database Indexes**: Comprehensive indexing strategy implemented for view performance
- ✅ **Performance Validation**: Performance test suite validates O(1) query behavior regardless of workflow complexity
- ✅ **Idiomatic Rails Integration**: `has_one :readiness_status` and `has_one :execution_context` associations working

**Key Files Implemented:**
- `db/views/tasker_step_readiness_statuses_v01.sql` - Step readiness calculation view
- `db/views/tasker_task_execution_contexts_v01.sql` - Task statistics and execution context view
- `db/migrate/*_create_tasker_step_readiness_statuses.rb` - View creation migration
- `db/migrate/*_create_tasker_task_execution_contexts.rb` - Task context view migration
- `db/migrate/*_add_indexes_for_step_readiness_views.rb` - Performance indexes
- `app/models/tasker/step_readiness_status.rb` - ReadOnly AR model for step readiness
- `app/models/tasker/task_execution_context.rb` - ReadOnly AR model for task context
- `spec/performance/query_optimization_spec.rb` - Comprehensive performance validation (10/10 tests passing)

### **✅ COMPLETED: Phase 2A - Core Processing Optimization (DONE)**

**Major Query Pattern Migrations:**
- ✅ **StepGroup DAG Traversal**: Replaced recursive `step.parents.empty?` and `step.children` traversal with efficient `StepReadinessStatus` batch queries (O(N²) → O(1))
- ✅ **EventPayloadBuilder Fail-Fast**: Removed all fallback patterns that caused N+1s, enforced scenic view architecture with clean error handling
- ✅ **WorkflowStep.find_step_by_name**: Optimized recursive DAG traversal with batch step ID collection and single preload query
- ✅ **Task Finalization Performance**: StepGroup operations now use 2-3 scenic view queries regardless of workflow complexity

**Files Optimized:**
- `lib/tasker/task_handler/step_group.rb` - Comprehensive scenic view integration for all step analysis
- `lib/tasker/events/event_payload_builder.rb` - Fail-fast scenic view enforcement with clean architecture
- `app/models/tasker/workflow_step.rb` - Optimized DAG traversal methods with batch loading patterns

### **🔄 IN PROGRESS: Phase 2B - Remaining Systematic Migration**

**Remaining High-Priority Targets:**
- ❌ **API Serialization Layer**: `WorkflowStepSerializer` parent/child ID queries (identified for Phase 3A Step Relationship View)
- ❌ **GraphQL Integration**: `WorkflowStepType` parent/child field N+1s (identified for Phase 3A Step Relationship View)
- ❌ **Task Diagram Generation**: `build_step_edges` method individual child loading (identified for Phase 3A Step Relationship View)

**Phase 2B Status**: **STRATEGIC PAUSE** - Remaining items are better addressed by Phase 3A Step Relationship View rather than individual fixes

### **🔄 PLANNED: Remaining Implementation Work**

**Priority 1: Core Query Migration (Next 1-2 weeks)**
- [ ] Audit and migrate all state checking patterns to use scenic views
- [ ] Update event payload building to use efficient view-based queries
- [ ] Migrate main workflow processing loops to use TaskExecutionContext recommendations
- [ ] Update state machine dependency checking logic

**Priority 2: Advanced Optimizations (Future)**
- [ ] Implement materialized views if needed for expensive calculations
- [ ] Add view performance monitoring and alerting
- [ ] Create automated performance regression tests
- [ ] Document view-based optimization patterns

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

### **Phase 1: Core Views & Models (COMPLETED ✅)**

**Deliverables**:
- ✅ Create `step_readiness_status` view with comprehensive readiness logic
- ✅ Create `task_execution_context` view with workflow statistics
- ✅ Implement corresponding ActiveRecord models
- ✅ Add database indexes to support view performance
- ✅ Create migration for view deployment

**Technical Tasks COMPLETED**:
```bash
# ✅ Generated Scenic views - DONE
rails generate scenic:model step_readiness_status
rails generate scenic:model task_execution_context

# ✅ Created supporting indexes - DONE
rails generate migration AddIndexesForStepReadinessViews
```

**Performance Validation COMPLETED ✅**:
- ✅ Performance test suite created and passing (10/10 tests)
- ✅ Query count verified to be non-linear (≤3 queries regardless of complexity)
- ✅ Scaling factor verified to be ≤2.0x (sub-linear performance scaling)

### **Phase 2: Query Pattern Migration (IN PROGRESS 🔄)**

**Deliverables COMPLETED ✅**:
- ✅ Refactor `WorkflowStep.get_viable_steps` to use views
- ✅ Add convenience methods for view-based state checking
- ✅ Create idiomatic Rails associations (`has_one :readiness_status`, `has_one :execution_context`)

**Deliverables REMAINING ❌**:
- ❌ Update `TaskHandler.handle` processing loop to use `TaskExecutionContext`
- ❌ Migrate `all_parents_complete?` and related methods throughout codebase
- ❌ Update `EventPayloadBuilder` to use readiness views
- ❌ Audit state machine logic in `lib/tasker/state_machine/step_state_machine.rb`

**Critical Migration Points Identified**:

1. **State Machine Dependency Checking** (`lib/tasker/state_machine/step_state_machine.rb`):
   ```ruby
   # CURRENT: Likely has N+1 patterns in step_dependencies_met? method
   # NEEDS: Migration to use StepReadinessStatus.dependencies_satisfied
   ```

2. **Event Payload Building** (`lib/tasker/events/event_payload_builder.rb`):
   ```ruby
   # CURRENT: Likely loads step associations individually
   # NEEDS: Use StepReadinessStatus for dependency info, retry status, etc.
   ```

3. **Main Workflow Processing** (TaskHandler core loops):
   ```ruby
   # CURRENT: Multiple queries to check task and step states
   # NEEDS: Use TaskExecutionContext.recommended_action for processing decisions
   ```

**Performance Validation COMPLETED ✅**:
- ✅ Create benchmark tests comparing old vs. new query patterns
- ✅ Verify query count reduction (achieved: ≤3 queries per workflow operation)
- ✅ Validate correctness of readiness determinations

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

**Document Status**: PHASE 1 COMPLETE, PHASE 2 IN PROGRESS
**Last Updated**: June 2025
**Next Review**: After Phase 2 migration completion
**Owner**: Development Team
**Dependencies**: ✅ Scenic gem installed and configured, ✅ Views deployed and working

**Current Priority**: Systematic migration of existing query patterns to use scenic views
**Estimated Completion**: 2-3 weeks for complete migration
**Performance Gains**: Infrastructure validated, full gains pending complete migration

## 🔍 **PHASE 2 CONTINUATION: SYSTEMATIC MIGRATION STRATEGY**

### **🔍 COMPREHENSIVE CODEBASE AUDIT (COMPLETED)**
*This audit identifies all remaining N+1 patterns and inefficient queries throughout the codebase*

#### **Category 1: State Machine & Dependency Checking [HIGH PRIORITY]**

**Location**: `lib/tasker/state_machine/step_state_machine.rb`
- ✅ **FIXED**: `step_dependencies_met?` method - now uses scenic views instead of N+1 parent queries
- **Status**: Already migrated to fail-fast scenic view approach

**Location**: `lib/tasker/task_handler/step_group.rb`
- ❌ **NEEDS MIGRATION**: `find_incomplete_steps` method (lines 71-86)
  - **Problem**: `step.parents.empty?` and `step.children` cause N+1 queries when building step groups
  - **Pattern**: `prior_incomplete_steps << step if Constants::VALID_STEP_COMPLETION_STATES.exclude?(step.status)`
  - **Impact**: Called during task finalization for every step in workflow
  - **Solution**: Replace with scenic view batch queries

- ❌ **NEEDS MIGRATION**: `build_this_pass_complete_steps` and related methods (lines 99-126)
  - **Problem**: Individual `step.status` calls for each step in collection
  - **Pattern**: `Constants::VALID_STEP_COMPLETION_STATES.include?(step.status)`
  - **Solution**: Use scenic view data instead of individual status checks

#### **Category 2: API & Serialization Layers [MEDIUM PRIORITY]**

**Location**: `app/serializers/tasker/workflow_step_serializer.rb`
- ❌ **NEEDS MIGRATION**: Parent/child ID serialization (lines 11-21)
  - **Problem**: `object.children.pluck(:workflow_step_id)` and `object.parents.pluck(:workflow_step_id)`
  - **Pattern**: N+1 queries when serializing step collections via API
  - **Impact**: API endpoints that return multiple steps cause 2 extra queries per step
  - **Solution**: Add parent/child IDs to scenic views or preload associations

**Location**: `app/controllers/tasker/workflow_steps_controller.rb`
- ❌ **NEEDS OPTIMIZATION**: Query pattern improvement (lines 44-45)
  - **Current**: `@task.workflow_steps.includes(:named_step)`
  - **Problem**: Still triggers N+1s for status, parent/child data in serializer
  - **Solution**: Include scenic view associations in preloading

**Location**: `app/graphql/tasker/graph_ql_types/workflow_step_type.rb`
- ❌ **NEEDS MIGRATION**: GraphQL parent/child fields (lines 25-26)
  - **Problem**: GraphQL queries trigger N+1s for `parents` and `children` fields
  - **Impact**: Any GraphQL query requesting step relationships
  - **Solution**: Use DataLoader or preloading with scenic view data

#### **Category 3: Workflow Processing Logic [HIGH PRIORITY]**

**Location**: `app/models/tasker/workflow_step.rb`
- ✅ **PARTIALLY FIXED**: Several methods already migrated to scenic views
- ❌ **NEEDS MIGRATION**: `find_step_by_name` method (lines 126-144)
  - **Problem**: `step.children.to_a` causes N+1 when recursively traversing workflow DAG
  - **Pattern**: Recursive traversal without batching
  - **Solution**: Use scenic view or batch loading for tree traversal

**Location**: `app/models/tasker/task_diagram.rb`
- ❌ **NEEDS MIGRATION**: `build_step_edges` method (lines 191-211)
  - **Problem**: `step.children.each` iteration loads child associations individually
  - **Pattern**: Building diagram representations with N+1 child lookups
  - **Solution**: Preload all edges for task before building diagram

#### **Category 4: Event & Payload Building [MEDIUM PRIORITY]**

**Location**: `lib/tasker/events/event_payload_builder.rb`
- ✅ **PARTIALLY OPTIMIZED**: Already uses scenic views when available
- ❌ **NEEDS MIGRATION**: Fallback patterns (lines 354-376)
  - **Problem**: Falls back to direct `step.status` calls when scenic view unavailable
  - **Pattern**: "Graceful degradation" that still causes N+1s
  - **Solution**: Remove fallbacks, enforce scenic view usage (fail-fast approach)

#### **Category 5: Step Processing & Finalization [MEDIUM PRIORITY]**

**Location**: Various test support and orchestration files
- ❌ **NEEDS MIGRATION**: Test helpers using direct association traversal
  - **Problem**: `step.parents.all?` patterns in test support (lines in factory helpers)
  - **Impact**: Test performance and hidden N+1s in test scenarios
  - **Solution**: Update test helpers to use scenic views

### **📋 MIGRATION PRIORITY ROADMAP**

#### **Phase 2A: Core Processing Loops [Days 1-3]**
1. **StepGroup dependency traversal** - High impact on finalization
2. **Workflow step traversal methods** - Used in core processing
3. **Event payload fallback removal** - Enforce scenic view architecture

#### **Phase 2B: API & User Interface [Days 4-5]**
1. **WorkflowStep serializer optimization** - API performance
2. **Controller preloading updates** - Web interface responsiveness
3. **GraphQL field optimization** - Modern API performance

#### **Phase 2C: Supporting Systems [Days 6-7]**
1. **Task diagram generation** - Administrative interface performance
2. **Test helper updates** - Development velocity
3. **Documentation and validation** - Architecture compliance

### **🎯 EXPECTED PERFORMANCE GAINS**

**Before Migration**:
- Task finalization: N+1 for each step's status + N+1 for parent/child checks = O(N²)
- API endpoints: N+1 for step status + N+1 for parents + N+1 for children = O(3N)
- GraphQL queries: Unbounded N+1s depending on field selection
- Event publishing: Conditional N+1s based on fallback usage

**After Migration**:
- Task finalization: 1-2 queries via scenic views regardless of task complexity = O(1)
- API endpoints: 1 query + preloaded associations = O(1)
- GraphQL queries: DataLoader batching + scenic views = O(1)
- Event publishing: No fallbacks, guaranteed O(1) performance

**Estimated Improvement**: 80-95% query reduction for workflows with >10 steps

### **Immediate Next Steps (Priority Order)**

**Step 1: Comprehensive Codebase Audit (1-2 days)**
- Search for all patterns that check step states individually
- Identify all locations using associations like `step.parents.all?(&:complete?)`
- Map all event payload building locations that might have N+1 patterns
- Document state machine dependency checking logic

**Step 2: State Machine Integration (2-3 days)**
- Review `lib/tasker/state_machine/step_state_machine.rb` - DONE ✅
- Update StepGroup traversal logic to use scenic views
- Replace individual status checking patterns
- Update test helpers to use scenic view patterns

**Step 3: API & Serialization Migration (2-3 days)**
- Update WorkflowStep serializer to preload parent/child data efficiently
- Optimize controller includes to use scenic view associations
- Implement GraphQL DataLoader patterns for step relationships
- Update API documentation to reflect performance improvements

**Step 4: Event System Complete Migration (1-2 days)**
- Remove all fallback patterns from EventPayloadBuilder
- Enforce scenic view availability (fail-fast approach)
- Update event publishing to guarantee O(1) performance
- Add monitoring to detect scenic view architecture violations

**Step 5: Workflow Processing Complete Migration (2-3 days)**
- Update WorkflowStep.find_step_by_name for efficient DAG traversal
- Optimize task diagram generation to batch edge loading
- Replace remaining association traversal patterns
- Comprehensive testing of core workflow scenarios

**Step 6: Performance Validation & Documentation (1-2 days)**
- Expand performance test suite to cover all migrated areas
- Benchmark before/after performance improvements
- Update architectural documentation
- Create monitoring dashboard for query performance

## 🔍 **ADDITIONAL VIEW OPPORTUNITIES IDENTIFIED**

*During the optimization audit, several additional patterns emerged that would benefit from specialized scenic views*

### **📊 Category A: Step Relationship & DAG Navigation [HIGH IMPACT]**

#### **View Opportunity 1: `tasker_step_dag_relationships`**
**Problem Patterns Identified**:
- **API Serialization N+1s**: `object.children.pluck(:workflow_step_id)` and `object.parents.pluck(:workflow_step_id)` in `WorkflowStepSerializer` (lines 11-21)
- **GraphQL N+1s**: Parent/child field queries in `WorkflowStepType` causing unbounded N+1s (lines 25-26)
- **DAG Traversal Inefficiency**: `find_step_by_name` method using `step.children.to_a` during recursive traversal
- **Task Diagram Generation**: `build_step_edges` method loading child associations individually (lines 191-211)
- **StepGroup Root Finding**: `step.parents.empty?` checks for identifying root steps

**Current Query Impact**:
- API endpoints: N+1 for step status + N+1 for parents + N+1 for children = O(3N)
- GraphQL queries: Unbounded N+1s depending on field selection depth
- Task diagram: N+1 for each step's children during edge building

**Proposed View Structure**:
```sql
-- db/views/tasker_step_dag_relationships_v01.sql
SELECT
  ws.workflow_step_id,
  ws.task_id,
  ws.named_step_id,

  -- Parent/Child relationship data (pre-calculated)
  COALESCE(parent_data.parent_ids, '[]'::jsonb) as parent_step_ids,
  COALESCE(child_data.child_ids, '[]'::jsonb) as child_step_ids,
  COALESCE(parent_data.parent_count, 0) as parent_count,
  COALESCE(child_data.child_count, 0) as child_count,

  -- DAG position information
  CASE WHEN COALESCE(parent_data.parent_count, 0) = 0 THEN true ELSE false END as is_root_step,
  CASE WHEN COALESCE(child_data.child_count, 0) = 0 THEN true ELSE false END as is_leaf_step,

  -- Depth calculation for DAG traversal optimization
  depth_info.max_depth_to_leaf,
  depth_info.min_depth_from_root

FROM tasker_workflow_steps ws

LEFT JOIN (
  SELECT
    to_step_id,
    jsonb_agg(from_step_id ORDER BY from_step_id) as parent_ids,
    count(*) as parent_count
  FROM tasker_workflow_step_edges
  GROUP BY to_step_id
) parent_data ON parent_data.to_step_id = ws.workflow_step_id

LEFT JOIN (
  SELECT
    from_step_id,
    jsonb_agg(to_step_id ORDER BY to_step_id) as child_ids,
    count(*) as child_count
  FROM tasker_workflow_step_edges
  GROUP BY from_step_id
) child_data ON child_data.from_step_id = ws.workflow_step_id

LEFT JOIN (
  -- Recursive CTE for depth calculation (PostgreSQL-specific)
  WITH RECURSIVE step_depths AS (
    -- Base case: root steps (no parents)
    SELECT
      ws.workflow_step_id,
      0 as depth_from_root,
      ws.task_id
    FROM tasker_workflow_steps ws
    WHERE NOT EXISTS (
      SELECT 1 FROM tasker_workflow_step_edges e
      WHERE e.to_step_id = ws.workflow_step_id
    )

    UNION ALL

    -- Recursive case: steps with parents
    SELECT
      e.to_step_id,
      sd.depth_from_root + 1,
      sd.task_id
    FROM step_depths sd
    JOIN tasker_workflow_step_edges e ON e.from_step_id = sd.workflow_step_id
    WHERE sd.depth_from_root < 50 -- Prevent infinite recursion
  )
  SELECT
    workflow_step_id,
    MIN(depth_from_root) as min_depth_from_root,
    -- Calculate max depth to leaf (would need another CTE)
    NULL as max_depth_to_leaf
  FROM step_depths
  GROUP BY workflow_step_id
) depth_info ON depth_info.workflow_step_id = ws.workflow_step_id
```

**Expected Performance Gains**:
- API serialization: O(3N) → O(1)
- GraphQL queries: Unbounded N+1s → O(1) with DataLoader
- DAG traversal: O(N) per level → O(1) root identification
- Task diagrams: O(N) edge queries → O(1) batch loading

**Implementation Priority**: HIGH - Solves multiple categories of N+1s

---

### **📊 Category B: Enhanced Task Processing Context [MEDIUM IMPACT]**

#### **View Opportunity 2: `tasker_task_workflow_summaries`**
**Problem Patterns Identified**:
- **TaskHandler Processing Logic**: Multiple queries to determine next action during workflow processing
- **Event Payload Building**: Loading task statistics individually for each event
- **Workflow Orchestration**: Determining viable steps and processing strategy

**Current Query Impact**:
- Task processing: Multiple individual queries for step counts, status checks, viability assessment
- Event publishing: Repeated task statistics calculation across different event types

**Proposed View Structure**:
```sql
-- db/views/tasker_task_workflow_summaries_v01.sql
SELECT
  t.task_id,
  -- Include all existing TaskExecutionContext fields
  tec.total_steps,
  tec.pending_steps,
  tec.in_progress_steps,
  tec.completed_steps,
  tec.failed_steps,
  tec.ready_steps,
  tec.execution_status,
  tec.recommended_action,
  tec.completion_percentage,
  tec.health_status,

  -- Enhanced processing context
  root_steps.root_step_ids,
  root_steps.root_step_count,

  -- Blocking analysis with specific step identification
  blocking_info.blocked_step_ids,
  blocking_info.blocking_reasons,

  -- Next processing recommendation with actionable step IDs
  CASE
    WHEN tec.ready_steps > 0 THEN ready_steps.ready_step_ids
    ELSE NULL
  END as next_executable_step_ids,

  -- Processing strategy recommendation
  CASE
    WHEN tec.ready_steps > 5 THEN 'batch_parallel'
    WHEN tec.ready_steps > 1 THEN 'small_parallel'
    WHEN tec.ready_steps = 1 THEN 'sequential'
    ELSE 'waiting'
  END as processing_strategy

FROM tasker_tasks t
JOIN tasker_task_execution_contexts tec ON tec.task_id = t.task_id

LEFT JOIN (
  SELECT
    task_id,
    jsonb_agg(workflow_step_id ORDER BY workflow_step_id) as root_step_ids,
    count(*) as root_step_count
  FROM tasker_step_readiness_statuses srs
  WHERE srs.total_parents = 0
  GROUP BY task_id
) root_steps ON root_steps.task_id = t.task_id

LEFT JOIN (
  SELECT
    task_id,
    jsonb_agg(workflow_step_id ORDER BY workflow_step_id) as ready_step_ids
  FROM tasker_step_readiness_statuses srs
  WHERE srs.ready_for_execution = true
  GROUP BY task_id
) ready_steps ON ready_steps.task_id = t.task_id

LEFT JOIN (
  SELECT
    task_id,
    jsonb_agg(workflow_step_id ORDER BY workflow_step_id) as blocked_step_ids,
    jsonb_agg(blocking_reason ORDER BY workflow_step_id) as blocking_reasons
  FROM tasker_step_readiness_statuses srs
  WHERE srs.ready_for_execution = false
    AND srs.current_state IN ('pending', 'failed')
  GROUP BY task_id
) blocking_info ON blocking_info.task_id = t.task_id
```

**Expected Performance Gains**:
- Task processing decisions: Multiple queries → Single query with actionable recommendations
- Event payload building: Repeated statistics calculation → Pre-calculated comprehensive context
- Workflow orchestration: Manual step discovery → Direct step ID arrays for processing

**Implementation Priority**: MEDIUM - Enhances processing efficiency but not blocking current functionality

---

### **📊 Category C: Specialized Performance Views [FUTURE ENHANCEMENT]**

#### **View Opportunity 3: `tasker_step_performance_metrics`**
**Use Case**: Performance monitoring and analysis
**Proposed View**: Step execution patterns, retry frequencies, average durations, failure patterns
**Implementation Priority**: LOW - Observability enhancement, not performance critical

#### **View Opportunity 4: `tasker_workflow_dependency_analysis`**
**Use Case**: Complex dependency validation and cycle detection
**Proposed View**: Dependency chains, critical path analysis, potential bottlenecks
**Implementation Priority**: LOW - Advanced analytics, not day-to-day operations

---

### **🎯 RECOMMENDED IMPLEMENTATION SEQUENCE**

#### **Phase 3A: Step Relationship View (Next Priority)**
1. **Immediate Impact**: Solves API, GraphQL, and DAG traversal N+1s
2. **Broad Application**: Benefits multiple system components simultaneously
3. **Low Risk**: Well-understood relationship data, straightforward implementation

#### **Phase 3B: Enhanced Task Workflow Summaries (Future)**
1. **Processing Optimization**: Improves task processing loop efficiency
2. **Event System Enhancement**: Richer payloads with pre-calculated context
3. **Orchestration Support**: Better decision-making data for workflow management

#### **Phase 3C: Specialized Views (Future Enhancement)**
1. **Observability**: Performance monitoring and analysis capabilities
2. **Advanced Features**: Dependency analysis and optimization insights
3. **Analytics**: Historical pattern analysis and prediction capabilities

### **🏗️ IMPLEMENTATION APPROACH FOR PHASE 3A**

**Step 1: Create StepDagRelationship View & Model**
```bash
# Generate scenic model
rails generate scenic:model step_dag_relationship

# Create supporting indexes
rails generate migration AddIndexesForStepDagRelationships
```

**Step 2: Update Affected Components**
- `WorkflowStepSerializer`: Use pre-calculated parent/child IDs
- `WorkflowStepType` (GraphQL): Implement DataLoader with relationship view
- `TaskDiagram.build_step_edges`: Batch load all edges via view
- `WorkflowStep.find_step_by_name`: Use root step identification for optimization

**Step 3: Performance Validation**
- Update performance test suite to validate relationship view queries
- Benchmark API endpoint response times
- Test GraphQL query performance with complex relationship selections

**Expected Timeline**: 3-5 days for complete implementation and testing
