# Tasker Event-Driven Architecture: Complete Migration Strategy - PHASE 3

## 🎯 **Current Mission: Complete StepExecutor Implementation for Event-Driven Step Processing**

You're continuing work on **completely migrating** Tasker's workflow system from imperative TaskHandler coordination to declarative event-driven orchestration. **Previous sessions have built a solid foundation - now it's time to complete the core step execution logic.**

## ✅ **CRITICAL ARCHITECTURAL PROGRESS ACHIEVED**

### **What's Already Working (Don't Break These!)**

#### Infrastructure Layer - 100% Operational
- **✅ IdempotentStateTransitions Concern**: DRY state management across orchestration
- **✅ Event-Driven System**: Coordinator, Orchestrator, ViableStepDiscovery operational
- **✅ Application Initialization**: Orchestration guaranteed active via Rails initializer
- **✅ Zero Runaway Jobs**: Complete elimination of cascading job enqueues
- **✅ Enhanced TelemetrySubscriber**: Consistent constant usage throughout (no more string literals!)
- **✅ TaskReenqueuer**: Clean separation of concerns (decisions vs. implementation mechanics)
- **✅ Event Infrastructure**: Complete constants for re-enqueue, finalization, and orchestration events

#### Recent Architectural Enhancements (Completed This Session)
- **✅ TaskReenqueuer Extraction**: `lib/tasker/orchestration/task_reenqueuer.rb` with comprehensive lifecycle events
- **✅ TelemetrySubscriber Consistency**: All handlers use constants instead of string literals
- **✅ Smart Event Conversion**: `event_identifier_to_string()` handles constant-to-string mapping
- **✅ Coordinator Architecture Fix**: Clean class structure with proper telemetry subscriber initialization
- **✅ Event Constants Added**: `TASK_REENQUEUE_*`, `TASK_FINALIZATION_*`, `TASK_STATE_UNCLEAR`

#### Test Status Validation
- ✅ **PASSING**: `spec/models/tasker/task_spec.rb` - Core models with enhanced orchestration
- ✅ **ORCHESTRATION INITIALIZATION**: Coordinator properly starts orchestration system
- ✅ **TELEMETRY INTEGRATION**: TelemetrySubscriber connects with constant-based event handling
- ❌ **EXPECTED ISSUE**: `spec/models/tasker/task_handler_spec.rb` - Steps stay "in_progress" (this is your target!)

## 🎯 **Your Primary Goal: Complete StepExecutor Implementation**

**Current Issue**: TaskHandler test fails because steps transition to "in_progress" but never complete. The orchestration system has infrastructure but incomplete step execution logic.

**Root Cause**: We have a hybrid system where:
- ✅ **Infrastructure**: Event-driven orchestration components are operational
- ❌ **Step Processing**: StepExecutor doesn't actually execute step handlers or complete transitions
- ❌ **Integration**: Step handlers not connected to event-driven execution flow

### Target Architecture (Current State vs. Goal)

```
CURRENT STATE: Hybrid System
├── Coordinator ✅ (initializes properly)
├── ViableStepDiscovery ✅ (finds steps correctly)
├── StepExecutor ❌ (transitions to in_progress but doesn't complete)
├── TaskFinalizer ✅ (handles decisions properly)
├── TaskReenqueuer ✅ (clean re-enqueue mechanics)
└── TelemetrySubscriber ✅ (consistent constant usage)

GOAL STATE: Complete Event-Driven Execution
├── Coordinator ✅ (already working)
├── ViableStepDiscovery ✅ (already working)
├── StepExecutor ✅ (COMPLETE step execution with handlers) ← **YOUR TARGET**
├── TaskFinalizer ✅ (already working)
├── TaskReenqueuer ✅ (already working)
└── TelemetrySubscriber ✅ (already working)
```

## 🛠 **Key Implementation Target: StepExecutor Enhancement**

**File**: `lib/tasker/orchestration/step_executor.rb`

**Current Incomplete State**:
```ruby
def execute_single_step(step)
  step.state_machine.transition_to!(:in_progress)
  # MISSING: actual step execution
  # MISSING: handler invocation
  # MISSING: completion transition
end
```

**Required Complete Implementation**:
```ruby
def execute_single_step(task, sequence, step, task_handler)
  # Transition to in_progress
  step.state_machine.transition_to!(:in_progress)

  # Get step handler (integrate with existing plugin patterns)
  handler = task_handler.get_step_handler(step)

  # Execute step handler (preserve plugin patterns)
  handler.handle(task, sequence, step)

  # Complete step (event-driven state transition)
  step.state_machine.transition_to!(:complete)

  # Fire completion events
  fire_step_completion_events(step)

  step
rescue StandardError => e
  # Handle errors gracefully
  handle_step_error(step, e)
  step
end
```

**Key Requirements**:
1. **Preserve Plugin Patterns**: StepTemplate and StepHandler must work unchanged
2. **Extract TaskHandler Logic**: Move step execution logic to orchestration
3. **Maintain Step Dependencies**: Ensure DAG traversal and dependency resolution works
4. **Handle Errors Gracefully**: Error states should transition properly
5. **Fire Events**: Use direct constants (not string literals) for consistency

## 📋 **Implementation Strategy**

### Phase 3.1: Complete StepExecutor (CURRENT TARGET)
**Goal**: Make StepExecutor fully replace TaskHandler's step processing logic

**Key Integration Points**:
1. **Step Handler Access**: Use `task_handler.get_step_handler(step)` to maintain plugin compatibility
2. **Handler Execution**: Call `handler.handle(task, sequence, step)` as existing plugins expect
3. **State Transitions**: Use state machine for `pending → in_progress → complete` flow
4. **Error Handling**: Transition to `error` state on failures with proper event firing
5. **Event Integration**: Use constants like `Tasker::Constants::WorkflowEvents::STEPS_EXECUTION_COMPLETED`

### Phase 3.2: Validation and Testing
**Goal**: Ensure `spec/models/tasker/task_handler_spec.rb` passes with event-driven execution

**Success Criteria**:
1. **Steps Execute**: Real step handlers get called and complete properly
2. **State Transitions**: Proper "pending" → "in_progress" → "complete" flow
3. **Plugin Patterns Work**: DummyTask handlers work with orchestration system
4. **Event-Driven Flow**: No imperative loops or direct status updates
5. **Error Recovery**: Failed steps transition to error state appropriately

## 🔧 **Key Files to Work With**

### Primary Target
- **`lib/tasker/orchestration/step_executor.rb`** - Your main implementation target

### Supporting Files (Don't break these!)
- **`lib/tasker/orchestration/viable_step_discovery.rb`** - Step discovery & queueing ✅
- **`lib/tasker/orchestration/task_finalizer.rb`** - Decision making ✅
- **`lib/tasker/orchestration/task_reenqueuer.rb`** - Re-enqueue mechanics ✅
- **`lib/tasker/events/subscribers/telemetry_subscriber.rb`** - Consistent event handling ✅

### Reference Implementation (Legacy)
- **`lib/tasker/task_handler/instance_methods.rb`** - Logic to extract and migrate
- **`spec/mocks/dummy_task.rb`** - Real step handlers that must work with new system

### Test Target
- **`spec/models/tasker/task_handler_spec.rb`** - This should pass when StepExecutor is complete

## 📋 **Testing Strategy**

### Primary Validation Target
```bash
# This should pass when StepExecutor is complete:
bundle exec rspec spec/models/tasker/task_handler_spec.rb --format documentation
```

### Success Indicators
1. **No "in_progress" State Stacking**: Steps should complete, not stay stuck in in_progress
2. **Real Handler Execution**: Actual step logic runs (not just state transitions)
3. **Plugin Compatibility**: DummyTask handlers work seamlessly
4. **Event Consistency**: All events fired using constants (no string literals)

## 🧭 **Implementation Approach**

### Start Here
1. **Examine Current StepExecutor**: `lib/tasker/orchestration/step_executor.rb`
2. **Study TaskHandler Pattern**: `lib/tasker/task_handler/instance_methods.rb` (extract the step execution logic)
3. **Understand Plugin Integration**: `spec/mocks/dummy_task.rb` (preserve these patterns)
4. **Test Incrementally**: Run the TaskHandler spec to validate progress

### Key Success Pattern
The goal is **complete functional replacement** of TaskHandler's step processing while preserving the plugin patterns that make Tasker extensible. You're not wrapping the old system - you're completing the new one.

## 🚨 **Critical Success Factors**

1. **Complete Migration Mindset**: Replace TaskHandler step processing functionality completely
2. **Preserve Plugin Value**: Step templates and handlers must work unchanged
3. **Event-Driven Native**: Build for orchestration system, not legacy compatibility
4. **Real-World Integration**: Use actual plugin classes (DummyTask) not synthetic tests
5. **Consistent Event Handling**: Use constants throughout (building on TelemetrySubscriber improvements)

## 🎯 **Expected Outcome**

When complete, you should have:
- ✅ **Full StepExecutor Implementation**: Steps execute completely through handlers to completion
- ✅ **Plugin Compatibility**: All existing step handlers work unchanged
- ✅ **Event-Driven Execution**: Pure orchestration-based workflow processing
- ✅ **Test Validation**: `spec/models/tasker/task_handler_spec.rb` passes
- ✅ **Clean Architecture**: No imperative loops, pure event-driven flow

**The goal is a complete, clean event-driven workflow system that preserves Tasker's extensibility while eliminating all imperative coordination complexity.** 🚀
