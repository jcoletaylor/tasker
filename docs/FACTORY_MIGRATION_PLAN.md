# Factory-Based Testing Migration Plan

## Overview
This document outlines the systematic migration from mock/double-heavy tests to factory-based testing for the Tasker Rails engine. The goal is to improve test reliability, catch integration issues, and provide more confidence in the system's behavior.

## ✅ Completed: State Machine Tests + Major Architecture Improvements

### State Machine Test Migration
- **File**: `spec/lib/tasker/state_machine/task_state_machine_spec.rb`
- **Status**: ✅ COMPLETE - All 29 tests passing
- **Improvements**:
  - Replaced `instance_double` with real `create(:task)` objects
  - Tests now verify actual database persistence and state transitions
  - Discovered and fixed real integration issues with Statesman

- **File**: `spec/lib/tasker/state_machine/step_state_machine_spec.rb`
- **Status**: ✅ COMPLETE - All 33 tests passing
- **Improvements**:
  - Replaced `instance_double` with real `create(:workflow_step)` objects
  - Tests now verify actual step dependencies and state transitions
  - Fixed dependency checking bug in guard clauses
  - Resolved event registration issues

### 🎯 **Major Architecture Improvements Completed**

#### 1. **Proper Workflow Execution Enforcement**
**Problem Identified**: Direct PENDING → COMPLETE transitions were bypassing normal workflow execution
**Solution Implemented**:
- **Enforced proper workflow**: PENDING → IN_PROGRESS → COMPLETE
- **Added manual resolution path**: PENDING → RESOLVED_MANUALLY (for valid manual intervention)
- **Prevented workflow bypass**: Steps must be executed (IN_PROGRESS) before completion
- **Result**: ✅ Architectural integrity maintained, no workflow shortcuts allowed

#### 2. **Comprehensive Event System Overhaul**
**Problems Solved**:
- ❌ Unexpected transition warnings: `initial → complete. No event will be fired`
- ❌ Mix of string literals and constants in event registration
- ❌ Inefficient case/when statements for event mapping

**Solutions Implemented**:

**A. Complete Event Constant System** (`lib/tasker/constants.rb`):
```ruby
# State machine transition events (semantic, namespaced)
module TaskEvents
  INITIALIZE_REQUESTED = 'task.initialize_requested'
  START_REQUESTED = 'task.start_requested'
  COMPLETED = 'task.completed'
  # ... etc
end

# Legacy lifecycle events (backward compatibility)
module LegacyTaskEvents
  HANDLE = 'task.handle'
  ENQUEUE = 'task.enqueue'
  # ... etc
end

# Workflow orchestration events
module WorkflowEvents
  TASK_STARTED = 'workflow.task_started'
  VIABLE_STEPS_DISCOVERED = 'workflow.viable_steps_discovered'
  # ... etc
end
```

**B. Efficient HashMap-Based Event Mapping**:
```ruby
# Replaced O(n) case/when with O(1) hashmap lookup
TRANSITION_EVENT_MAP = {
  [nil, Constants::WorkflowStepStatuses::PENDING] => Constants::StepEvents::INITIALIZE_REQUESTED,
  [Constants::WorkflowStepStatuses::PENDING, Constants::WorkflowStepStatuses::IN_PROGRESS] => Constants::StepEvents::EXECUTION_REQUESTED,
  # ... comprehensive mapping including initial state transitions
}.freeze
```

**C. Complete Initial State Transition Coverage**:
- **Fixed**: All `[nil, target_state]` transitions now have proper event mappings
- **Result**: ✅ No more "unexpected transition" warnings
- **Coverage**: All possible Statesman transitions handled

**D. Publisher Event Registration Cleanup** (`lib/tasker/events/publisher.rb`):
- **Replaced**: String literals with constants throughout
- **Organized**: Events by category (state machine, legacy, workflow)
- **Eliminated**: Duplicate and unused event registrations
- **Result**: ✅ Single source of truth for all event names

#### 3. **Developer Experience & Type Safety**
**Improvements Delivered**:
- **IDE Autocomplete**: Full support for all event names
- **Type Safety**: Constants prevent typos and runtime errors
- **Maintainability**: Easy to add new events and transitions
- **Self-Documenting**: Clear categorization and semantic naming
- **Refactoring Safety**: Centralized event definitions

#### 4. **Performance Optimizations**
**Optimizations Implemented**:
- **O(1) Event Lookup**: HashMap-based transition mapping
- **Reduced String Allocation**: Frozen constants throughout
- **Efficient Registration**: Constant-based event registration
- **Memory Efficiency**: Eliminated duplicate string literals

### 🔍 **Real Bugs Discovered & Fixed Through Factory Testing**
1. **Step dependency guard clause bug**: Guard wasn't checking if dependencies were met
2. **Workflow bypass vulnerability**: Direct PENDING → COMPLETE transitions allowed
3. **Event registration gaps**: Missing events causing "unregistered event" errors
4. **Integration issues**: Real problems between Statesman and event system that mocks didn't catch

### 📊 **Final Test Results**
- **Combined State Machine Tests**: 62/62 tests passing ✅
- **No unexpected transition warnings** ✅
- **Clean test output** ✅
- **Proper workflow enforcement** ✅
- **Complete event system coverage** ✅

### 🚀 **Architecture Foundation Ready**
The system now has a **rock-solid foundation** for the declarative event-driven transformation outlined in `BETTER_LIFECYCLE_EVENTS.md`:

1. **Robust State Management**: Database-backed transitions with full audit trail
2. **Type-Safe Event System**: Constants throughout with comprehensive coverage
3. **Efficient Performance**: HashMap-based lookups and optimized event handling
4. **Architectural Integrity**: Proper workflow execution enforced
5. **Developer Experience**: IDE support, easy maintenance, clear documentation

This foundation makes the remaining factory migration and eventual declarative transformation much more reliable and maintainable.

## 🎯 Phase 1: Critical Model Tests (High Priority)

### 1.1 Step State Machine Tests
**File**: `spec/lib/tasker/state_machine/step_state_machine_spec.rb`
**Current Issues**: Heavy use of `instance_double` for steps and tasks
**Factory Solution**: Use `create(:workflow_step)` and `create(:task, :with_steps)`
**Benefits**: Test real step dependencies and state transitions

### 1.2 Workflow Step Model Tests
**File**: `spec/models/tasker/workflow_step_spec.rb`
**Current Issues**:
- Manual task creation with `task_handler.initialize_task!`
- Helper methods for step manipulation (`helper.reset_step_to_default`)
- Direct status updates bypassing state machines
**Factory Solution**:
```ruby
# Replace this:
task = task_handler.initialize_task!(helper.task_request({ reason: 'test' }))

# With this:
task = create(:task, :api_integration, :with_steps)
```

### 1.3 Task Handler Tests
**File**: `spec/models/tasker/task_handler_spec.rb`
**Current Issues**: Manual task creation and complex setup
**Factory Solution**: Use composite workflow factories for realistic scenarios

## 🎯 Phase 2: Integration Tests (Medium Priority)

### 2.1 API Integration Tests
**File**: `spec/tasks/integration_example_spec.rb`
**Current Issues**:
- Manual task and step creation
- Complex Faraday stubbing setup
- Manual step completion tracking
**Factory Solution**:
```ruby
# Replace manual setup with:
let(:workflow) { create(:api_integration_workflow, :with_dependencies) }
let(:task) { workflow }
```

### 2.2 YAML Integration Tests
**File**: `spec/tasks/integration_yaml_example_spec.rb`
**Similar improvements to API integration tests**

## 🎯 Phase 3: Request/Controller Tests (Medium Priority)

### 3.1 Tasks API Tests
**File**: `spec/requests/tasker/tasks_spec.rb`
**Current Issues**: Repetitive manual task creation for each test
**Factory Solution**:
```ruby
# Replace repetitive setup with:
let(:pending_task) { create(:task, :pending) }
let(:completed_task) { create(:task, :complete, :with_steps) }
let(:api_workflow) { create(:api_integration_workflow) }
```

### 3.2 Workflow Steps API Tests
**File**: `spec/requests/tasker/workflow_steps_spec.rb`
**Similar factory-based improvements**

## 🎯 Phase 4: GraphQL Tests (Lower Priority)

### 4.1 GraphQL Task Tests
**File**: `spec/graphql/tasker/task_spec.rb`
**Factory Solution**: Use pre-configured workflow factories for GraphQL testing

### 4.2 GraphQL Workflow Step Tests
**File**: `spec/graphql/tasker/workflow_step_spec.rb`
**Similar factory-based improvements**

## Implementation Strategy

### Step 1: Create Enhanced Factory Traits
Add more specific traits to support complex test scenarios:

```ruby
# Enhanced task factory traits
trait :with_api_steps do
  after(:create) do |task|
    create(:workflow_step, :fetch_cart, task: task)
    create(:workflow_step, :fetch_products, task: task)
    create(:workflow_step, :validate_products, task: task)
    # ... with proper dependencies
  end
end

trait :partially_complete do
  after(:create) do |task|
    # Complete first 2 steps, leave others pending
    task.workflow_steps.limit(2).each do |step|
      step.state_machine.transition_to!(:in_progress)
      step.state_machine.transition_to!(:complete)
    end
  end
end

trait :with_errors do
  after(:create) do |task|
    # Set one step to error state
    step = task.workflow_steps.first
    step.state_machine.transition_to!(:in_progress)
    step.state_machine.transition_to!(:error)
  end
end
```

### Step 2: Create Test Helper Methods
```ruby
# spec/support/workflow_test_helpers.rb
module WorkflowTestHelpers
  def complete_step(step)
    step.state_machine.transition_to!(:in_progress)
    step.state_machine.transition_to!(:complete)
  end

  def error_step(step, error_message = 'Test error')
    step.state_machine.transition_to!(:in_progress)
    step.state_machine.transition_to!(:error, metadata: { error: error_message })
  end

  def complete_workflow(task)
    task.workflow_steps.each { |step| complete_step(step) }
    task.state_machine.transition_to!(:in_progress)
    task.state_machine.transition_to!(:complete)
  end
end
```

### Step 3: Migration Checklist

For each test file:
- [ ] **Identify Mock Usage**: Find `instance_double`, `allow`, `expect` calls
- [ ] **Replace with Factories**: Use appropriate factory traits
- [ ] **Update Assertions**: Test real object state, not mocked behavior
- [ ] **Verify Integration**: Ensure tests catch real system issues
- [ ] **Run Tests**: Confirm all tests pass with real objects

## Expected Benefits

### 1. **Reliability Improvements**
- Tests will catch real integration issues between components
- Database constraint violations will be detected
- State machine integration problems will surface

### 2. **Maintenance Benefits**
- Less brittle tests (no mock setup to maintain)
- Easier to understand test scenarios
- Factory traits can be reused across multiple test files

### 3. **Development Confidence**
- Tests verify actual system behavior
- Refactoring is safer with integration tests
- New features can be tested against realistic data

### 4. **Performance Considerations**
- Factory creation is fast with proper database setup
- Can use `build_stubbed` for tests that don't need persistence
- Database transactions keep tests isolated

## Risk Mitigation

### 1. **Test Performance**
- Use database transactions for test isolation
- Consider `build_stubbed` for non-persistence tests
- Profile test suite performance before/after migration

### 2. **Test Complexity**
- Start with simple factory replacements
- Gradually add more complex scenarios
- Document factory usage patterns

### 3. **Backward Compatibility**
- Migrate one test file at a time
- Keep existing tests passing during migration
- Use feature flags if needed for gradual rollout

## Success Metrics

- [ ] **Test Reliability**: Reduced flaky test failures
- [ ] **Integration Coverage**: Tests catch real system issues
- [ ] **Maintainability**: Easier to add new test scenarios
- [ ] **Developer Experience**: Faster test development with factories
- [ ] **System Confidence**: Higher confidence in deployments

## Timeline

- **Week 1**: Phase 1 - Critical model tests (step state machine, workflow step model)
- **Week 2**: Phase 1 continued - Task handler tests
- **Week 3**: Phase 2 - Integration tests (API and YAML)
- **Week 4**: Phase 3 - Request/controller tests
- **Week 5**: Phase 4 - GraphQL tests and cleanup

## Next Actions

1. **Immediate**: Start with `spec/lib/tasker/state_machine/step_state_machine_spec.rb`
2. **This Week**: Complete Phase 1 critical model tests
3. **Document**: Create examples of successful factory patterns
4. **Review**: Get team feedback on factory-based approach

---

*This migration represents a fundamental shift toward more reliable, maintainable testing that provides greater confidence in the Tasker system's behavior.*
