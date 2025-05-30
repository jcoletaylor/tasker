# Tasker Event-Driven Architecture Continuation Prompt

## 🎯 **Current Mission: Complete Event-Driven Step Execution Logic**

You're continuing work on transforming Tasker's workflow system from imperative to event-driven architecture. **Infrastructure layer is COMPLETE and working** - now we need to complete the step execution logic.

## ✅ **What's Already Working (Don't Break These!)**

### Infrastructure Layer - 100% Operational
- **IdempotentStateTransitions Concern**: `lib/tasker/concerns/idempotent_state_transitions.rb` provides DRY state management
- **Runaway Job Issue**: COMPLETELY FIXED - zero cascading job enqueues
- **Orchestration System**: Event-driven architecture active via `config/initializers/tasker_orchestration.rb`
- **Clean Architecture**: Single workflow path, no dual systems or fallback complexity

### Test Status Validation
- ✅ **PASSING**: `spec/examples/workflow_orchestration_example_spec.rb` - Event system working
- ✅ **PASSING**: `spec/lib/tasker/state_machine_spec.rb` - State transitions working
- ✅ **PASSING**: `spec/models/tasker/task_spec.rb` - Core models working
- ❌ **EXPECTED FAILURE**: `spec/models/tasker/task_handler_spec.rb` - Steps stay "in_progress" (THIS IS YOUR TARGET)

## 🎯 **Your Primary Goal**

**Fix the failing TaskHandler test** by completing the event-driven step execution logic:

### Problem Description
- **Test**: `spec/models/tasker/task_handler_spec.rb:57` expects steps to complete but they stay "in_progress"
- **Root Cause**: Test calls `task_handler.handle(task)` (imperative) but TaskRunnerJob uses orchestration (event-driven)
- **Missing Piece**: Event-driven system starts steps but doesn't complete them because step execution logic is incomplete

### Expected Behavior
```ruby
# This test should pass:
task_handler.handle(task)
step_states = task.workflow_steps.map(&:status)
expect(step_states).to(eq(%w[complete complete complete complete]))
```

## 🛠 **Key Files & Components**

### Critical Implementation Files
1. **`lib/tasker/orchestration/step_executor.rb`** - Currently starts steps, needs to complete them
2. **`lib/tasker/orchestration/viable_step_discovery.rb`** - Discovers steps, queues for execution
3. **`lib/tasker/step_handler/base.rb`** - Step handlers that need event-driven integration
4. **`lib/tasker/task_handler/instance_methods.rb`** - Contains imperative logic to migrate

### State Management (Already Working)
- **`lib/tasker/concerns/idempotent_state_transitions.rb`** - Use `safe_transition_to()` for all state changes
- **State Machine Integration** - Tasks/steps have `.state_machine.transition_to!()` methods

### Event Flow (Already Working)
- **Coordinator** starts task → **Orchestrator** handles state events → **ViableStepDiscovery** finds steps → **StepExecutor** starts steps
- **Missing**: StepExecutor needs to actually execute step handlers and complete steps

## 📋 **Implementation Strategy**

### Phase 1: Complete StepExecutor Logic
The `StepExecutor.execute_steps` method currently transitions steps to "in_progress" but doesn't:
1. **Call the actual step handlers** (like DummyTask::Handler)
2. **Process step results** and transition to "complete"
3. **Handle step errors** and transition to "error"

### Phase 2: Step Handler Integration
Connect existing step handlers to the event-driven flow:
- Step handlers in `spec/mocks/dummy_task.rb` should work with event system
- Preserve all existing handler logic while making it event-driven

### Phase 3: Validation
- `spec/models/tasker/task_handler_spec.rb` should pass
- Maintain all currently passing tests
- Verify no runaway job issues

## 🔍 **Key Implementation Details**

### StepExecutor Enhancement Pattern
```ruby
# Current (incomplete):
def execute_single_step(step)
  step.state_machine.transition_to!(:in_progress)
  # MISSING: actual step execution
end

# Target (complete):
def execute_single_step(step)
  step.state_machine.transition_to!(:in_progress)

  # Get and execute step handler
  handler = get_step_handler(step)
  handler.handle(task, sequence, step)

  # Transition to complete on success
  step.state_machine.transition_to!(:complete)
end
```

### Use Existing Patterns
- **State Transitions**: Always use `safe_transition_to(step, target_state)` from IdempotentStateTransitions
- **Event Firing**: Use existing `Tasker::LifecycleEvents.fire()` patterns
- **Error Handling**: Follow patterns in `lib/tasker/task_handler/instance_methods.rb`

## 🧪 **Testing Approach**

### Primary Validation
```bash
# This should pass when you're done:
bundle exec rspec spec/models/tasker/task_handler_spec.rb:57 --format documentation

# Make sure these stay passing:
bundle exec rspec spec/examples/workflow_orchestration_example_spec.rb:60 --format documentation
bundle exec rspec spec/lib/tasker/state_machine_spec.rb --format progress
```

### Success Criteria
- Steps complete through event-driven system (not just start)
- Zero job enqueue spam in test output
- All existing passing tests remain passing

## 📖 **Reference Documentation**

### Context Documents
- **`docs/BETTER_LIFECYCLE_EVENTS.md`** - Full project context and progress
- **Recent Achievements** documented in file header showing infrastructure completion

### Implementation Patterns
- **DRY State Transitions**: Use IdempotentStateTransitions concern methods
- **Event-Driven Flow**: Follow existing Orchestrator → ViableStepDiscovery → StepExecutor pattern
- **Clean Architecture**: Single execution path, no fallback complexity

## 🚨 **Critical Success Factors**

1. **Don't Break What's Working** - Infrastructure layer is complete and tested
2. **Follow Existing Patterns** - Use established event flow and state transition patterns
3. **Complete the Missing Piece** - Step execution logic is the only gap
4. **Validate Success** - TaskHandler test should pass with event-driven execution

**Start by examining `lib/tasker/orchestration/step_executor.rb` and the failing test to understand exactly what's missing in the step execution flow.**

---

## 📋 **Quick Current State Summary**

### Architectural Achievements This Session
- ✅ **Created IdempotentStateTransitions Concern** - Eliminated repeated state checking patterns
- ✅ **Fixed Runaway Job Issue** - 100% elimination of cascading job enqueues
- ✅ **Guaranteed Orchestration Startup** - Rails initializer ensures system always ready
- ✅ **Simplified TaskRunnerJob** - Only uses orchestration, no fallback complexity
- ✅ **Clean Component Architecture** - Single workflow path, terminal operations

### What's Ready for You
- **Infrastructure Layer**: Event bus, state machines, orchestration components all working
- **Test Validation**: Clear success/failure criteria with specific target test
- **Implementation Gap**: Well-defined missing piece (step execution logic)
- **Existing Patterns**: Clear examples to follow for state transitions and event handling

### Your Starting Point
1. Run `bundle exec rspec spec/models/tasker/task_handler_spec.rb:57` to see the failing test
2. Examine `lib/tasker/orchestration/step_executor.rb` to see what's missing
3. Look at `lib/tasker/task_handler/instance_methods.rb` for imperative patterns to migrate
4. Implement step execution logic following existing event-driven patterns

**You have all the infrastructure - just need to complete the step execution flow!** 🚀
