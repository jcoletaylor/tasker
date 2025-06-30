# Task Execution Control Flow

This document describes the orchestration patterns and control flow for task execution in Tasker, with particular focus on the coordination between WorkflowCoordinator and TaskFinalizer components.

## Overview

Tasker's task execution follows a sophisticated orchestration pattern that supports both coordinated workflow execution and autonomous task management. The system uses a **dual finalization strategy** to handle different execution contexts while maintaining consistency and preventing race conditions.

## Core Components

### 1. WorkflowCoordinator
- **Role**: Primary orchestration engine for task execution
- **Responsibility**: Manages step-by-step execution within a single workflow session
- **Scope**: Single task execution from start to completion

### 2. TaskFinalizer
- **Role**: Task state management and completion logic
- **Responsibility**: Determines task completion, handles state transitions, manages reenqueuing
- **Scope**: Can operate independently or as part of coordinated execution

### 3. Execution Context Separation
The system distinguishes between two execution contexts:
- **Coordinated Execution**: Within an active WorkflowCoordinator session
- **Autonomous Execution**: Independent task management and cleanup

## Control Flow Patterns

### Pattern 1: Coordinated Workflow Execution (Production Primary Path)

```
TaskRunnerJob.perform(task_id)
    ↓
TaskHandler.handle(task)
    ↓
WorkflowCoordinator.execute_workflow(task, task_handler)
    ↓
[Step Execution Loop]
    ↓
WorkflowCoordinator → task_handler.finalize(task, sequence, processed_steps)
    ↓
TaskHandler.finalize → task_finalizer.finalize_task_with_steps(task, sequence, processed_steps)
    ↓
FinalizationProcessor.finalize_with_steps(task, processed_steps, finalizer)
    ↓
TaskFinalizer.finalize_task(task.task_id, synchronous: true)  ← SYNCHRONOUS
```

**Key Characteristics:**
- **Single-threaded execution** within the workflow coordinator
- **Synchronous finalization** prevents reenqueuing/step execution conflicts
- **Rich event publishing** with processed step context
- **Coordinated state management** with workflow awareness

### Pattern 2: Autonomous Task Management (Event-Driven)

```
Event: TaskFinalizer.handle_no_viable_steps(event)
    ↓
TaskFinalizer.finalize_task(task_id)  ← Default: synchronous: false
    ↓
[Autonomous decision making]
    ↓
May reenqueue task or execute ready steps independently
```

**Key Characteristics:**
- **Event-driven activation** outside workflow sessions
- **Asynchronous finalization** allows autonomous orchestration decisions
- **Independent reenqueuing** based on task state analysis
- **Cleanup and continuation** logic for orphaned or stalled tasks

## Synchronous vs Asynchronous Finalization

### Synchronous Finalization (`synchronous: true`)

**When Used:**
- Called from `FinalizationProcessor.finalize_with_steps`
- During coordinated workflow execution
- At the end of a WorkflowCoordinator session

**Behavior:**
```ruby
if synchronous
  # In synchronous mode, we can't actually execute steps here
  # The calling code should handle step execution
  Rails.logger.info("TaskFinalizer: Task #{task.task_id} ready for synchronous step execution")
else
  # In asynchronous mode, reenqueue immediately for step execution
  finalizer.reenqueue_task_with_context(task, context,
                                        reason: Constants::TaskFinalization::ReenqueueReasons::READY_STEPS_AVAILABLE)
end
```

**Purpose:**
- **Prevents execution conflicts** with active WorkflowCoordinator
- **Defers orchestration decisions** to the coordinating workflow
- **Maintains state consistency** without competing execution attempts
- **Enables event publishing** while respecting execution boundaries

### Asynchronous Finalization (`synchronous: false`)

**When Used:**
- Default behavior for standalone finalization calls
- Event-driven task cleanup (`handle_no_viable_steps`)
- Independent task management scenarios

**Behavior:**
- **Can reenqueue tasks** for further processing
- **Can execute ready steps** autonomously
- **Makes independent orchestration decisions**
- **Handles cleanup and continuation** logic

## Event Flow and Observability

### Coordinated Execution Events
```
1. publish_finalization_started(task, processed_steps, context)
2. [Standard finalization logic with synchronous: true]
3. publish_finalization_completed(task, processed_steps, final_context)
```

**Event Payload Includes:**
- `processed_steps_count`
- `execution_status`
- `health_status` 
- `completion_percentage`
- `total_steps`, `ready_steps`, `failed_steps`
- `recommended_action`

### Autonomous Execution Events
Standard task state transition events without detailed step context.

## State Management

### Task State Transitions
Both execution patterns handle the same core state transitions:

```
PENDING → IN_PROGRESS → COMPLETE/FAILED
```

### Coordination States
Additional states managed during coordinated execution:
- **READY_STEPS_AVAILABLE**: Steps ready for execution
- **AWAITING_DEPENDENCIES**: Waiting for step dependencies
- **STEPS_IN_PROGRESS**: Active step processing
- **BLOCKED_BY_FAILURES**: Error state requiring intervention

## Reenqueuing Strategy

### Synchronous Context (No Reenqueuing)
- Task state transitions occur
- Events are published
- **Control returns to WorkflowCoordinator**
- Coordinator decides next actions

### Asynchronous Context (Autonomous Reenqueuing)
- Task state transitions occur
- **TaskFinalizer makes reenqueuing decisions**
- Tasks are queued for continued processing
- Independent of any workflow session

## Error Handling and Recovery

### Coordinated Execution
- Errors bubble up to WorkflowCoordinator
- Coordinated retry and recovery logic
- Workflow-aware error handling

### Autonomous Execution  
- Independent error handling
- Automatic reenqueuing for recoverable failures
- Isolated failure management

## Design Rationale

### Why Two Execution Patterns?

1. **Execution Conflict Prevention**: Prevents race conditions between WorkflowCoordinator and TaskFinalizer when both might attempt step execution

2. **Orchestration Control**: Allows WorkflowCoordinator to maintain full control over execution timing and step ordering

3. **Event Integration**: Enables rich observability events without interfering with execution flow

4. **Clean Separation**: Separates "finalization as part of workflow execution" from "finalization as independent task cleanup"

5. **Architectural Flexibility**: Supports both coordinated workflow sessions and autonomous task management

### Performance Considerations

- **Reduced Reenqueuing**: Synchronous finalization eliminates unnecessary reenqueuing during active workflow sessions
- **Optimized Event Publishing**: Rich events only published when step context is available
- **Efficient State Management**: Single state transition cycle per execution context

## Best Practices

### For Framework Development

1. **Always use `finalize_task_with_steps`** when finalizing from workflow execution
2. **Use default `finalize_task`** for event-driven cleanup
3. **Respect the synchronous flag** in finalization logic
4. **Publish appropriate events** for each execution context

### For Task Handler Implementation

1. **Call `finalize()` method** at end of task execution - it handles coordination automatically
2. **Don't call TaskFinalizer directly** from task handlers
3. **Implement `update_annotations()`** hook for custom finalization logic

### For Event Subscribers

1. **Handle both execution patterns** in event subscribers
2. **Check event context** to understand execution pattern
3. **Don't assume step context** in all finalization events

## Troubleshooting

### Common Issues

1. **Duplicate Execution**: Usually caused by calling both execution patterns simultaneously
2. **Missing Events**: Check if using appropriate finalization method for context
3. **State Inconsistencies**: Verify synchronous flag usage in custom finalization logic

### Debugging Steps

1. Check TaskFinalizer logs for synchronous flag values
2. Trace event publishing to identify execution pattern
3. Verify WorkflowCoordinator session boundaries
4. Monitor reenqueuing patterns for autonomous vs coordinated execution

## Future Considerations

The dual finalization pattern provides a foundation for:
- **Distributed orchestration** across multiple coordinators
- **Hierarchical workflow management** with nested coordination
- **Advanced retry strategies** with context-aware reenqueuing
- **Performance optimizations** through execution pattern analysis