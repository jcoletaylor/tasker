# Better Lifecycle Events: Transforming Imperative Workflows into Declarative Event-Driven Architecture

## Preamble: Current State Analysis and Transformation Strategy

### Current Implementation Deep Dive

The Tasker system has evolved into a sophisticated workflow engine with impressive event infrastructure, but it suffers from a fundamental architectural tension: **robust event definitions paired with imperative workflow execution**.

#### Existing Event Infrastructure (Sophisticated but Underutilized)

The system already contains remarkable event infrastructure that's currently underutilized:

**Event Definition System**:
- `EventDefinition` class with factory methods for task/step/workflow/telemetry events
- `EventRegistry` singleton managing 20+ predefined events with validation
- `StateTransition` class with predefined TASK_TRANSITIONS and STEP_TRANSITIONS
- `EventSchema` with dry-validation contracts for payload validation
- Comprehensive event categorization and metadata support

**Current Event Usage Pattern**:
- Events fired via `Tasker::LifecycleEvents.fire()` using ActiveSupport::Notifications
- Primary purpose: observational telemetry and instrumentation
- Events report what happened, but don't control what happens next
- 15+ event firing points throughout TaskHandler::InstanceMethods

#### The Imperative Workflow Problem

The core workflow logic in `TaskHandler::InstanceMethods` is entirely imperative:

**Main Processing Loop** (`handle` method):
```ruby
loop do
  task.reload
  sequence = get_sequence(task)
  viable_steps = find_viable_steps(task, sequence)
  break if viable_steps.empty?
  processed_steps = handle_viable_steps(task, sequence, viable_steps)
  break if blocked_by_errors?(task, sequence, processed_steps)
end
finalize(task, final_sequence, all_processed_steps)
```

**State Management Issues**:
- Direct `task.update!({ status: CONSTANT })` calls throughout codebase
- No audit trail of state changes or transition reasons
- Race conditions possible with concurrent task processing
- Complex error handling and retry logic scattered across methods
- Finalization logic with multiple re-enqueue scenarios hard to follow

**Step Processing Complexity**:
- `handle_one_step` method contains complex error handling, retry logic, and state updates
- Concurrent vs sequential processing branches with different error handling
- DAG traversal logic mixed with execution logic in `find_viable_steps`

#### Existing Event Registry Capabilities (Ready for Activation)

The system already defines comprehensive state transitions that are perfect for Statesman:

**Predefined Task Transitions**:
- `nil → pending` (task.initialize_requested)
- `pending → in_progress` (task.start_requested)  
- `in_progress → complete` (task.completed)
- `in_progress → error` (task.failed)
- `error → pending` (task.retry_requested)

**Predefined Step Transitions**:
- `nil → pending` (step.initialize_requested)
- `pending → in_progress` (step.execution_requested)
- `in_progress → complete` (step.completed)
- `in_progress → error` (step.failed)
- `error → pending` (step.retry_requested)

### Desired Future State: Declarative Event-Driven Architecture

Transform the system to use **events as the primary drivers** of workflow execution:

1. **Statesman State Machines**: Replace direct status updates with state machine transitions
2. **Event-Driven Orchestration**: Workflow logic triggered by state transition events
3. **Publisher/Subscriber Pattern**: Decouple workflow orchestration from state management
4. **Unified Event System**: Single event bus handling both state transitions and orchestration
5. **Declarative Workflow Definition**: Steps declare what events they respond to, not imperative sequencing

#### Target Architecture Components

**State Layer** (Statesman):
- TaskStateMachine and StepStateMachine with database-backed transitions
- Automatic audit trail with transition metadata
- Race condition resolution at database level

**Orchestration Layer** (Dry::Events):
- WorkflowOrchestrator subscribes to state transition events
- Publishes orchestration events (viable_steps_discovered, batch_ready, etc.)
- StepExecutor subscribes to orchestration events and triggers state transitions

**Integration Layer**:
- EventRegistry coordinates both Statesman and dry-events
- Unified event validation and schema enforcement
- Telemetry integration for both state and orchestration events

## Implementation Strategy: Phased Transformation

### Phase 1: Statesman Foundation with Existing Event Integration

#### Step 1.1: State Machine Infrastructure ✅ 
**Status**: COMPLETE - Statesman gem already in tasker.gemspec

#### Step 1.2: Create State Machines Using Existing Definitions

**Goal**: Implement Statesman state machines using the predefined transitions from EventRegistry.

**Key Implementation**: Leverage existing `StateTransition::TASK_TRANSITIONS` and `StateTransition::STEP_TRANSITIONS`:

**Files to Create**:
```
lib/tasker/state_machines/
  ├── task_state_machine.rb
  ├── step_state_machine.rb
  └── base_state_machine.rb
app/models/
  ├── task_transition.rb
  └── workflow_step_transition.rb
db/migrate/
  ├── xxx_create_task_transitions.rb
  └── xxx_create_workflow_step_transitions.rb
```

**TaskStateMachine Implementation**:
```ruby
class TaskStateMachine < Tasker::StateMachines::BaseStateMachine
  # Use existing Constants for states
  state Constants::TaskStatuses::PENDING, initial: true
  state Constants::TaskStatuses::IN_PROGRESS
  state Constants::TaskStatuses::COMPLETE
  state Constants::TaskStatuses::ERROR
  state Constants::TaskStatuses::CANCELLED
  state Constants::TaskStatuses::RESOLVED_MANUALLY

  # Import transitions from existing StateTransition definitions
  StateTransition::TASK_TRANSITIONS.each do |transition|
    transition from: transition.from_state&.to_sym, 
               to: transition.to_state.to_sym
  end

  # Integration hooks for event system
  after_transition do |task, transition, metadata|
    # Fire corresponding lifecycle event
    event_name = determine_event_name(transition)
    EventRegistry.instance.fire_transition_event(event_name, task, transition, metadata)
  end
end
```

**Model Integration**:
```ruby
# app/models/task.rb (updates)
class Task < ApplicationRecord
  has_many :task_transitions, autosave: false, dependent: :destroy
  
  include Statesman::Adapters::ActiveRecordQueries[
    transition_class: TaskTransition,
    initial_state: Constants::TaskStatuses::PENDING
  ]
  
  def state_machine
    @state_machine ||= TaskStateMachine.new(
      self, 
      transition_class: TaskTransition,
      association_name: :task_transitions
    )
  end
  
  # Compatibility method for existing code
  def status
    state_machine.current_state
  end
  
  # Deprecate direct status updates
  def status=(new_status)
    Rails.logger.warn "Direct status assignment deprecated. Use state machine transitions."
    state_machine.transition_to!(new_status)
  end
end
```

#### Step 1.3: Hybrid State Management (Preserve Existing API)

**Goal**: Replace direct status updates while maintaining existing API compatibility.

**Migration Strategy**:
- Keep existing `status` columns during transition period
- Add compatibility layer that delegates to state machine
- Gradually migrate all direct `update!({ status: ... })` calls
- Create data migration for existing records

**Compatibility Layer**:
```ruby
module Tasker::StateMachine::Compatibility
  def update_status!(new_status, metadata = {})
    # New way: use state machine
    state_machine.transition_to!(new_status, metadata)
    
    # Compatibility: also update status column until migration complete
    update_columns(status: new_status) if respond_to?(:update_columns)
  end
end
```

### Phase 2: Event-Driven Workflow Orchestration

#### Step 2.1: Publisher/Subscriber Architecture

**Goal**: Transform imperative workflow logic into event-driven orchestration.

**New Architecture Components**:

**WorkflowOrchestrator** (Subscriber):
```ruby
class Tasker::WorkflowOrchestrator
  include Dry::Events::Publisher[:workflow]
  
  # Subscribe to state transition events
  def self.subscribe_to_state_events
    EventRegistry.instance.subscribe('task.state_changed') do |event|
      new.handle_task_state_change(event)
    end
    
    EventRegistry.instance.subscribe('step.state_changed') do |event|
      new.handle_step_state_change(event)
    end
  end
  
  def handle_task_state_change(event)
    case event[:new_state]
    when Constants::TaskStatuses::IN_PROGRESS
      publish('workflow.task_started', task_id: event[:task_id])
    when Constants::TaskStatuses::COMPLETE
      publish('workflow.task_completed', task_id: event[:task_id])
    end
  end
  
  def handle_step_state_change(event)
    case event[:new_state]
    when Constants::WorkflowStepStatuses::COMPLETE
      # Trigger viable step discovery
      publish('workflow.step_completed', {
        task_id: event[:task_id],
        step_id: event[:step_id]
      })
    end
  end
end
```

**ViableStepDiscovery** (Subscriber):
```ruby
class Tasker::ViableStepDiscovery
  include Dry::Events::Publisher[:workflow]
  
  def self.subscribe_to_orchestration_events
    WorkflowOrchestrator.subscribe('workflow.step_completed') do |event|
      new.discover_viable_steps(event[:task_id])
    end
    
    WorkflowOrchestrator.subscribe('workflow.task_started') do |event|
      new.discover_viable_steps(event[:task_id])
    end
  end
  
  def discover_viable_steps(task_id)
    task = Task.find(task_id)
    sequence = get_sequence(task) # Extract from TaskHandler
    viable_steps = find_viable_steps(task, sequence) # Extract from TaskHandler
    
    if viable_steps.any?
      publish('workflow.viable_steps_discovered', {
        task_id: task_id,
        step_ids: viable_steps.map(&:id),
        processing_mode: determine_processing_mode(task)
      })
    else
      publish('workflow.no_viable_steps', { task_id: task_id })
    end
  end
end
```

**StepExecutor** (Subscriber):
```ruby
class Tasker::StepExecutor
  def self.subscribe_to_workflow_events
    ViableStepDiscovery.subscribe('workflow.viable_steps_discovered') do |event|
      new.execute_steps(event)
    end
  end
  
  def execute_steps(event)
    steps = WorkflowStep.where(id: event[:step_ids])
    
    case event[:processing_mode]
    when 'concurrent'
      execute_steps_concurrently(steps)
    when 'sequential'
      execute_steps_sequentially(steps)
    end
  end
  
  private
  
  def execute_steps_concurrently(steps)
    futures = steps.map do |step|
      Concurrent::Future.execute { execute_single_step(step) }
    end
    
    futures.each(&:wait)
  end
  
  def execute_single_step(step)
    # Trigger state transition instead of direct execution
    step.state_machine.transition_to!(:in_progress, {
      triggered_by: 'workflow.viable_steps_discovered',
      executor: 'StepExecutor'
    })
  end
end
```

#### Step 2.2: Extract Core Workflow Logic

**Goal**: Extract the complex imperative logic from TaskHandler::InstanceMethods into event subscribers.

**Current Imperative Methods to Transform**:

1. **`handle` method main loop** → `WorkflowOrchestrator` event flow
2. **`find_viable_steps`** → `ViableStepDiscovery.discover_viable_steps`  
3. **`handle_viable_steps`** → `StepExecutor.execute_steps`
4. **`handle_one_step`** → `StepStateMachine` transition callbacks
5. **`finalize`** → `TaskFinalizer` subscriber
6. **`blocked_by_errors?`** → `ErrorHandler` subscriber

**Migration Strategy**:
- Extract each method into a dedicated subscriber class
- Preserve exact logic during extraction
- Connect via events instead of direct method calls
- Test each extraction independently

### Phase 3: State Machine Business Logic Integration

#### Step 3.1: Move Business Logic to State Machine Callbacks

**Goal**: Move task/step processing logic from imperative methods into Statesman transition callbacks.

**Task State Machine with Business Logic**:
```ruby
class TaskStateMachine < Tasker::StateMachines::BaseStateMachine
  # Guard transitions with business rules
  guard_transition(to: :in_progress) do |task, transition, metadata|
    # Task must have steps to start
    task.workflow_steps.exists? && !task.complete?
  end
  
  guard_transition(to: :complete) do |task, transition, metadata|
    # All steps must be in completion states
    step_group = StepGroup.build(task, get_sequence(task), [])
    step_group.complete?
  end
  
  # Before transition hooks for preparation
  before_transition(to: :in_progress) do |task, transition, metadata|
    # Ensure context is properly formatted
    task.context = ActiveSupport::HashWithIndifferentAccess.new(task.context)
    
    # Validate context against schema
    errors = validate_context(task.context)
    if errors.any?
      transition.metadata['validation_errors'] = errors
      raise Statesman::GuardFailedError, "Context validation failed: #{errors.join(', ')}"
    end
  end
  
  # After transition hooks for side effects
  after_transition(to: :in_progress) do |task, transition, metadata|
    # Fire orchestration event to start workflow
    WorkflowOrchestrator.publish('workflow.task_started', {
      task_id: task.id,
      transition_id: transition.id,
      metadata: metadata
    })
  end
  
  after_transition(to: :complete) do |task, transition, metadata|
    # Update completion timestamp
    task.update_columns(completed_at: Time.current)
    
    # Fire telemetry event
    Tasker::LifecycleEvents.fire(
      Tasker::LifecycleEvents::Events::Task::COMPLETE,
      { 
        task_id: task.id,
        task_name: task.name,
        completed_at: task.completed_at,
        transition_id: transition.id
      }
    )
  end
  
  after_transition(to: :error) do |task, transition, metadata|
    # Extract error information from metadata
    error_details = metadata['error_details'] || 'Unknown error'
    error_steps = metadata['error_steps'] || []
    
    # Fire error event with comprehensive details
    Tasker::LifecycleEvents.fire_error(
      Tasker::LifecycleEvents::Events::Task::ERROR,
      StandardError.new(error_details),
      {
        task_id: task.id,
        task_name: task.name,
        error_steps: error_steps,
        transition_id: transition.id
      }
    )
  end
end
```

**Step State Machine with Execution Logic**:
```ruby
class StepStateMachine < Tasker::StateMachines::BaseStateMachine
  # Guard transition for execution
  guard_transition(to: :in_progress) do |step, transition, metadata|
    # Check if step is viable (dependencies met)
    task = step.task
    Tasker::WorkflowStep.is_step_viable?(step, task)
  end
  
  # Before execution: setup and validation
  before_transition(to: :in_progress) do |step, transition, metadata|
    step.attempts = (step.attempts || 0) + 1
    step.last_attempted_at = Time.current
    
    # Create telemetry span context
    span_context = {
      span_name: "step.#{step.name}",
      task_id: step.task_id,
      step_id: step.id,
      step_name: step.name,
      attempt: step.attempts
    }
    
    transition.metadata['span_context'] = span_context
  end
  
  # After transition to in_progress: execute step
  after_transition(to: :in_progress) do |step, transition, metadata|
    # This is where the actual step execution happens
    span_context = transition.metadata['span_context']
    
    Tasker::LifecycleEvents.fire_with_span(
      Tasker::LifecycleEvents::Events::Step::HANDLE,
      span_context
    ) do
      begin
        # Get step handler and execute
        handler = get_step_handler(step)
        task = step.task
        sequence = get_sequence(task)
        
        # Execute the step logic
        handler.handle(task, sequence, step)
        
        # Transition to complete on success
        step.state_machine.transition_to!(:complete, {
          execution_successful: true,
          results: step.results
        })
        
      rescue StandardError => e
        # Transition to error on failure
        step.state_machine.transition_to!(:error, {
          error: e.message,
          backtrace: e.backtrace.join("\n"),
          exception_object: e
        })
      end
    end
  end
  
  # Handle successful completion
  after_transition(to: :complete) do |step, transition, metadata|
    step.update_columns(
      processed: true,
      processed_at: Time.current,
      results: step.results
    )
    
    # Fire completion event
    span_context = metadata['span_context'] || {}
    Tasker::LifecycleEvents.fire(
      Tasker::LifecycleEvents::Events::Step::COMPLETE,
      span_context.merge(step_results: step.results)
    )
    
    # Trigger workflow orchestration
    WorkflowOrchestrator.publish('workflow.step_completed', {
      task_id: step.task_id,
      step_id: step.id,
      transition_id: transition.id
    })
  end
  
  # Handle step errors with retry logic
  after_transition(to: :error) do |step, transition, metadata|
    error = metadata['error'] || 'Unknown error'
    
    # Update step with error details
    step.results ||= {}
    step.results = step.results.merge(
      error: error,
      backtrace: metadata['backtrace']
    )
    step.update_columns(
      processed: false,
      processed_at: nil,
      results: step.results
    )
    
    # Fire error event
    span_context = metadata['span_context'] || {}
    Tasker::LifecycleEvents.fire(
      Tasker::LifecycleEvents::Events::Step::ERROR,
      span_context.merge(error: error, step_results: step.results)
    )
    
    # Handle retry logic
    if step.attempts >= step.retry_limit
      # Max retries reached
      Tasker::LifecycleEvents.fire(
        Tasker::LifecycleEvents::Events::Step::MAX_RETRIES_REACHED,
        span_context.merge(attempts: step.attempts, retry_limit: step.retry_limit)
      )
    else
      # Schedule retry
      RetryScheduler.schedule_retry(step, transition)
    end
  end
end
```

#### Step 3.2: Retry and Error Handling via Events

**Goal**: Transform complex retry logic into event-driven scheduling.

**RetryScheduler** (New Component):
```ruby
class Tasker::RetryScheduler
  include Dry::Events::Publisher[:retry]
  
  def self.schedule_retry(step, transition)
    new.schedule_retry(step, transition)
  end
  
  def schedule_retry(step, transition)
    # Calculate backoff delay
    backoff_seconds = calculate_backoff(step)
    
    # Fire backoff event
    if backoff_seconds > 0
      Tasker::LifecycleEvents.fire(
        Tasker::LifecycleEvents::Events::Step::BACKOFF,
        {
          task_id: step.task_id,
          step_id: step.id,
          backoff_seconds: backoff_seconds,
          backoff_type: 'exponential',
          attempt: step.attempts
        }
      )
      
      # Schedule retry after backoff
      RetryJob.set(wait: backoff_seconds.seconds).perform_later(step.id)
    else
      # Immediate retry
      publish('retry.immediate', { step_id: step.id })
    end
  end
  
  private
  
  def calculate_backoff(step)
    # Use existing backoff logic or extract from API step handler
    base_delay = 1.0
    exponent = [step.attempts, 2].max
    max_delay = 30.0
    exponential_delay = [base_delay * (2**exponent), max_delay].min
    exponential_delay * rand # Add jitter
  end
end

# New Job for retry execution
class Tasker::RetryJob < ApplicationJob
  def perform(step_id)
    step = WorkflowStep.find(step_id)
    
    # Fire retry event
    Tasker::LifecycleEvents.fire(
      Tasker::LifecycleEvents::Events::Step::RETRY,
      {
        task_id: step.task_id,
        step_id: step.id,
        attempt: step.attempts + 1
      }
    )
    
    # Transition back to pending for re-execution
    step.state_machine.transition_to!(:pending, {
      triggered_by: 'retry_scheduler',
      previous_attempt: step.attempts
    })
  end
end
```

### Phase 4: Unified Event Registry Enhancement

#### Step 4.1: Enhanced EventRegistry for Hybrid System

**Goal**: Integrate existing EventRegistry with Statesman transitions and dry-events orchestration.

**Enhanced EventRegistry**:
```ruby
class Tasker::Events::EventRegistry
  # Add state machine integration
  def register_state_machine_events
    # Register Statesman transition events
    %w[task step].each do |entity_type|
      %w[before_transition after_transition].each do |callback_type|
        register_event(EventDefinition.new(
          name: "#{entity_type}.#{callback_type}",
          description: "#{entity_type.capitalize} #{callback_type.humanize}",
          category: 'state_machine',
          state_machine_event: true,
          telemetry_event: true
        ))
      end
    end
  end
  
  def register_orchestration_events
    # Register workflow orchestration events
    orchestration_events = [
      'workflow.task_started',
      'workflow.step_completed', 
      'workflow.viable_steps_discovered',
      'workflow.no_viable_steps',
      'workflow.batch_processing_started',
      'workflow.batch_processing_completed'
    ]
    
    orchestration_events.each do |event_name|
      register_event(EventDefinition.workflow_event(
        event_name,
        description: "Workflow orchestration: #{event_name}",
        state_machine_event: false
      ))
    end
  end
  
  # Enhanced event firing with validation
  def fire_transition_event(event_name, entity, transition, metadata)
    # Validate event against registered definition
    event_def = find_event!(event_name)
    
    # Build payload from transition context
    payload = {
      entity_type: entity.class.name.demodulize.downcase,
      entity_id: entity.id,
      from_state: transition.from_state,
      to_state: transition.to_state,
      transition_id: transition.id,
      metadata: metadata
    }
    
    # Validate payload against schema
    validate_event!(event_name, payload)
    
    # Fire both lifecycle event and orchestration event
    Tasker::LifecycleEvents.fire(event_name, payload)
    
    # Publish to dry-events subscribers if orchestration event
    if event_def.category == 'workflow'
      dry_events_publisher.publish(event_name, payload)
    end
  end
  
  private
  
  def dry_events_publisher
    @dry_events_publisher ||= Dry::Events::Publisher[:tasker_orchestration]
  end
end
```

#### Step 4.2: Event-Driven Task Finalization

**Goal**: Replace complex finalization logic with event-driven state determination.

**TaskFinalizer** (New Subscriber):
```ruby
class Tasker::TaskFinalizer
  include Dry::Events::Publisher[:workflow]
  
  def self.subscribe_to_events
    # Subscribe to workflow events that might trigger finalization
    WorkflowOrchestrator.subscribe('workflow.no_viable_steps') do |event|
      new.check_task_completion(event[:task_id])
    end
    
    # Subscribe to error events
    ErrorHandler.subscribe('error.task_blocked') do |event|
      new.handle_blocked_task(event[:task_id])
    end
  end
  
  def check_task_completion(task_id)
    task = Task.find(task_id)
    sequence = get_sequence(task)
    step_group = StepGroup.build(task, sequence, [])
    
    if step_group.complete?
      # All steps complete - transition task to complete
      task.state_machine.transition_to!(:complete, {
        triggered_by: 'workflow.no_viable_steps',
        finalizer: 'TaskFinalizer'
      })
    elsif step_group.pending?
      # Still have pending steps - re-enqueue task
      publish('workflow.task_reenqueue_requested', { task_id: task_id })
    else
      # Unclear state - investigate
      publish('workflow.task_state_unclear', { 
        task_id: task_id,
        step_group_state: step_group.debug_state
      })
    end
  end
  
  def handle_blocked_task(task_id)
    task = Task.find(task_id)
    
    # Transition to error state
    task.state_machine.transition_to!(:error, {
      triggered_by: 'error.task_blocked',
      finalizer: 'TaskFinalizer'
    })
  end
end
```

### Phase 5: Migration and Backward Compatibility

#### Step 5.1: Gradual Migration Strategy

**Goal**: Migrate from imperative to declarative without breaking existing functionality.

**Migration Phases**:

1. **Phase 5.1a**: Parallel System Operation
   - State machines handle new transitions
   - Existing TaskHandler methods still work
   - Events fired by both systems
   - Feature flag controls which system processes tasks

2. **Phase 5.1b**: Method-by-Method Migration
   - Extract `find_viable_steps` → `ViableStepDiscovery`
   - Extract `handle_viable_steps` → `StepExecutor`  
   - Extract `finalize` → `TaskFinalizer`
   - Each extraction preserves exact existing behavior

3. **Phase 5.1c**: State Machine Transition
   - Replace direct status updates with state machine calls
   - Migrate business logic to transition callbacks
   - Remove imperative workflow loop

**Feature Flag Implementation**:
```ruby
class TaskHandler::InstanceMethods
  def handle(task)
    if Tasker.configuration.use_declarative_workflow?
      # New way: trigger initial event
      task.state_machine.transition_to!(:in_progress, {
        triggered_by: 'task_handler.handle',
        handler_class: self.class.name
      })
    else
      # Old way: imperative processing
      start_task(task)
      # ... existing logic
    end
  end
end
```

#### Step 5.2: Data Migration and Audit Trail

**Goal**: Migrate existing state data to Statesman transitions with full audit trail.

**Migration Strategy**:
```ruby
class MigrateToStatesman < ActiveRecord::Migration[7.0]
  def up
    # Create initial transitions for existing tasks
    Task.find_each do |task|
      next if task.task_transitions.exists?
      
      # Create initial transition based on current status
      transition = task.task_transitions.create!(
        to_state: task.status,
        sort_key: 0,
        metadata: {
          migration: true,
          original_status: task.status,
          migrated_at: Time.current
        }
      )
      
      # If task has been updated, create subsequent transitions
      if task.updated_at > task.created_at
        transition = task.task_transitions.create!(
          from_state: nil,
          to_state: task.status,
          sort_key: 1,
          metadata: {
            migration: true,
            inferred_transition: true,
            migrated_at: Time.current
          }
        )
      end
    end
    
    # Same for workflow steps
    WorkflowStep.find_each do |step|
      # ... similar logic
    end
  end
end
```

### Phase 6: Advanced Orchestration Features

#### Step 6.1: Dynamic Workflow Configuration

**Goal**: Use events to support dynamic workflow behavior based on task configuration.

**Dynamic Event Routing**:
```ruby
class Tasker::DynamicWorkflowRouter
  def self.configure_task_workflow(task)
    # Route events based on task configuration
    case task.configuration['processing_mode']
    when 'high_priority'
      subscribe_to_priority_events(task)
    when 'batch_processing'
      subscribe_to_batch_events(task)
    when 'sequential_only'
      subscribe_to_sequential_events(task)
    else
      subscribe_to_default_events(task)
    end
  end
  
  private
  
  def self.subscribe_to_priority_events(task)
    # High priority tasks get dedicated event handlers
    PriorityStepExecutor.subscribe("workflow.viable_steps_discovered.#{task.id}") do |event|
      PriorityStepExecutor.new.execute_immediately(event)
    end
  end
end
```

#### Step 6.2: Advanced State Machine Features

**Goal**: Leverage Statesman's advanced features for complex workflow scenarios.

**Conditional State Machines**:
```ruby
class TaskStateMachine < Tasker::StateMachines::BaseStateMachine
  # Dynamic state machine behavior based on task type
  def self.for_task_type(task_type)
    case task_type
    when 'critical'
      CriticalTaskStateMachine
    when 'batch'
      BatchTaskStateMachine
    else
      self
    end
  end
  
  # Conditional transitions based on task properties
  guard_transition(to: :complete) do |task, transition, metadata|
    case task.task_type
    when 'critical'
      # Critical tasks require manual approval
      metadata['manual_approval'] == true
    when 'batch'
      # Batch tasks require all steps complete
      task.workflow_steps.where.not(status: 'complete').empty?
    else
      # Standard completion logic
      StepGroup.build(task, get_sequence(task), []).complete?
    end
  end
end

class CriticalTaskStateMachine < TaskStateMachine
  # Additional states for critical tasks
  state :pending_approval
  
  transition from: :in_progress, to: [:pending_approval, :complete, :error]
  transition from: :pending_approval, to: [:complete, :error]
  
  # Critical task specific callbacks
  after_transition(to: :pending_approval) do |task, transition, metadata|
    ApprovalRequestMailer.send_approval_request(task).deliver_later
  end
end
```

## Implementation Benefits

### Immediate Benefits
1. **Robust State Management**: Database-level conflict resolution via Statesman
2. **Complete Audit Trail**: Full history of all state changes with metadata and reasons
3. **Reduced Code Complexity**: Eliminate 500+ lines of imperative workflow logic
4. **Better Testing**: Clear separation between state transitions and business logic
5. **Event-Driven Debugging**: Rich event stream for troubleshooting workflow issues

### Long-term Benefits
1. **Scalability**: Proven Statesman solution handling billions of transitions in production
2. **Maintainability**: Well-documented, community-supported state machine library
3. **Extensibility**: Easy to add new states, transitions, and workflow behaviors
4. **Observability**: Rich transition history for analytics and performance optimization
5. **Concurrent Safety**: Built-in race condition handling and optimistic locking

### Developer Experience Benefits
1. **Declarative Workflow Definition**: Steps declare what events they respond to
2. **Simplified Error Handling**: Centralized retry and error recovery logic
3. **Easier Feature Development**: Add new workflow behaviors via event subscribers
4. **Better IDE Support**: Type-safe event definitions and state machine validation

## Migration Timeline

### Week 1: Foundation Setup
- **Phase 1 Complete**: Statesman state machines with existing event integration
- Create TaskStateMachine and StepStateMachine classes
- Add database migrations for transition tables
- Implement compatibility layer for existing status columns
- **Deliverable**: State machines operational in parallel with existing system

### Week 2: Event-Driven Orchestration
- **Phase 2 Complete**: Publisher/subscriber architecture
- Extract WorkflowOrchestrator, ViableStepDiscovery, StepExecutor
- Implement event-driven step discovery and execution
- Preserve all existing workflow logic during extraction
- **Deliverable**: Feature flag allowing choice between imperative and declarative workflows

### Week 3: Business Logic Migration
- **Phase 3 Complete**: State machine transition callbacks
- Move task/step processing logic to state machine callbacks
- Implement retry scheduling via events
- Add error handling and finalization subscribers
- **Deliverable**: Complete workflow processing via state machine events

### Week 4: Integration and Enhancement
- **Phase 4 Complete**: Enhanced EventRegistry integration
- Unify event firing between Statesman and dry-events
- Add dynamic workflow routing and configuration
- Complete data migration and remove compatibility layer
- **Deliverable**: Fully declarative event-driven workflow system

### Week 5: Polish and Optimization
- **Phase 5-6 Complete**: Advanced features and optimization
- Performance tuning for state machine queries
- Advanced workflow features (conditional transitions, dynamic routing)
- Comprehensive documentation and examples
- **Deliverable**: Production-ready declarative workflow system

## Risk Mitigation

### Technical Risks

**Data Migration Complexity**:
- *Risk*: Complex existing state data difficult to migrate to Statesman
- *Mitigation*: Gradual migration with parallel operation period
- *Contingency*: Rollback capability via feature flags

**Performance Impact**:
- *Risk*: Additional database queries for state machine operations
- *Mitigation*: Database indexing strategy and query optimization
- *Monitoring*: Performance benchmarks before/after migration

**Integration Complexity**:
- *Risk*: Complex interactions between Statesman and existing event system
- *Mitigation*: Incremental integration with extensive testing at each step
- *Validation*: Comprehensive test suite covering all workflow scenarios

### Operational Risks

**Service Disruption**:
- *Risk*: Migration causing task processing failures
- *Mitigation*: Feature flags allowing instant rollback to imperative system
- *Monitoring*: Real-time metrics on task success rates during migration

**Learning Curve**:
- *Risk*: Team unfamiliarity with event-driven architecture
- *Mitigation*: Documentation, training sessions, and gradual rollout
- *Support*: Pair programming during initial implementation

**Regression Risk**:
- *Risk*: Complex workflow edge cases not covered in declarative system
- *Mitigation*: Comprehensive test coverage and gradual feature migration
- *Validation*: A/B testing between imperative and declarative systems

### Business Risks

**Feature Development Velocity**:
- *Risk*: Slower development during migration period
- *Mitigation*: Maintain existing system for urgent features during migration
- *Timeline*: Plan migration during lower-priority development periods

## Success Criteria

### Technical Success Metrics

**State Management**:
- [ ] 100% of state transitions handled by Statesman state machines
- [ ] Zero data loss during migration from status columns to transitions
- [ ] Complete audit trail for all state changes with metadata
- [ ] Sub-100ms performance for 95% of state transitions
- [ ] Zero race condition conflicts in production

**Event System**:
- [ ] All workflow orchestration handled via event subscribers
- [ ] EventRegistry managing both Statesman and dry-events
- [ ] Complete schema validation for all event payloads
- [ ] Unified telemetry system capturing all events

**Code Quality**:
- [ ] Removal of 500+ lines of imperative workflow logic from TaskHandler
- [ ] Separation of state management from business logic
- [ ] 90%+ test coverage for all state machines and event subscribers
- [ ] Zero direct status column updates in application code

### Developer Experience Success Metrics

**Workflow Development**:
- [ ] New workflow features implemented via event subscribers
- [ ] Clear state machine definitions for all entity types
- [ ] Easy debugging through transition history and event logs
- [ ] Comprehensive documentation with examples

**Maintainability**:
- [ ] Statesman providing robust state management foundation
- [ ] Event-driven architecture enabling easy feature additions
- [ ] Clear separation of concerns between state and orchestration
- [ ] Simplified error handling and retry logic

### Operational Success Metrics

**Reliability**:
- [ ] Improved task processing reliability vs. imperative system
- [ ] Better error recovery through event-driven retry mechanisms
- [ ] Reduced support overhead for workflow-related issues
- [ ] Enhanced observability through comprehensive event logging

**Performance**:
- [ ] Maintained or improved task processing throughput
- [ ] Reduced memory usage through event-driven processing
- [ ] Better concurrent processing support via state machine safety
- [ ] Faster development of new workflow features

**Business Value**:
- [ ] Faster time-to-market for new workflow features
- [ ] Improved system reliability and user experience
- [ ] Better analytics and reporting through rich event data
- [ ] Enhanced ability to handle complex workflow requirements

## Implementation Checklist

### Phase 1: Foundation (Week 1)
- [ ] Create TaskStateMachine and StepStateMachine classes
- [ ] Add TaskTransition and WorkflowStepTransition models
- [ ] Create database migrations for transition tables
- [ ] Implement compatibility layer for existing status columns
- [ ] Add feature flag for declarative vs imperative processing
- [ ] Test state machine operations in parallel with existing system

### Phase 2: Orchestration (Week 2)
- [ ] Extract WorkflowOrchestrator from TaskHandler::InstanceMethods
- [ ] Extract ViableStepDiscovery from find_viable_steps method
- [ ] Extract StepExecutor from handle_viable_steps methods
- [ ] Implement dry-events publisher/subscriber connections
- [ ] Add event validation and schema enforcement
- [ ] Test event-driven workflow under feature flag

### Phase 3: Business Logic (Week 3)
- [ ] Move task processing logic to TaskStateMachine callbacks
- [ ] Move step processing logic to StepStateMachine callbacks
- [ ] Implement RetryScheduler for event-driven retry logic
- [ ] Add TaskFinalizer for event-driven task completion
- [ ] Create ErrorHandler for centralized error processing
- [ ] Test complete workflow via state machine events

### Phase 4: Integration (Week 4)
- [ ] Enhance EventRegistry for hybrid Statesman/dry-events system
- [ ] Implement unified event firing and validation
- [ ] Add transition metadata support for rich telemetry
- [ ] Create data migration for existing tasks and steps
- [ ] Remove compatibility layer and imperative code paths
- [ ] Validate complete migration to declarative system

### Phase 5: Enhancement (Week 5)
- [ ] Add dynamic workflow routing based on task configuration
- [ ] Implement conditional state machines for different task types
- [ ] Add advanced retry and error handling strategies
- [ ] Optimize database queries and indexing for state machines
- [ ] Create comprehensive documentation and examples
- [ ] Deploy to production with monitoring and rollback capability

This transformation represents a fundamental architectural evolution from imperative workflow processing to a sophisticated, declarative, event-driven system that leverages the existing robust event infrastructure while adding the reliability and auditability of Statesman state machines.