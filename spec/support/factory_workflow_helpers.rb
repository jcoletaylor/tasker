# frozen_string_literal: true

# Factory-based workflow helpers to replace manual task creation and step manipulation
# This replaces the imperative patterns from Helpers::TaskHelpers with declarative factory patterns
module FactoryWorkflowHelpers
  # Simple struct to replace sequence objects during migration
  # Provides compatibility while we transition away from imperative sequence objects
  SequenceStruct = Struct.new(:steps, :task) do
    def find_step_by_name(name)
      task.workflow_steps.joins(:named_step).find_by(named_step: { name: name })
    end
  end

  # Create a dummy task workflow with proper state machine setup
  def create_dummy_task_workflow(options = {})
    create(:dummy_task_workflow, **options, with_dependencies: true)
  end

  # Create a dummy task workflow variant (mimics DUMMY_TASK_TWO)
  def create_dummy_task_two_workflow(options = {})
    create(:dummy_task_workflow, :dummy_task_two, **options, with_dependencies: true)
  end

  # Find step by name in task (replacement for sequence.find_step_by_name)
  def find_step_by_name(task, step_name)
    task.workflow_steps.joins(:named_step).find_by(named_step: { name: step_name })
  end

  # Complete a step using state machine (replacement for helper.mark_step_complete)
  def complete_step_via_state_machine(step)
    step.state_machine.transition_to!(:in_progress)
    step.state_machine.transition_to!(:complete)
    step.update_columns(
      processed: true,
      processed_at: Time.current,
      results: { dummy: true, other: true }
    )
    step
  end

  # Reset step to pending using state machine (replacement for helper.reset_step_to_default)
  def reset_step_to_pending(step)
    # If step is not in pending state, we need to carefully handle the reset
    current_state = step.state_machine.current_state

    unless current_state == Tasker::Constants::WorkflowStepStatuses::PENDING
      # For testing purposes, manually reset the state
      # In production, this would be handled through proper workflow retry mechanisms
      step.update_columns(
        processed: false,
        processed_at: nil,
        in_process: false,
        results: { dummy: true }
      )

      # Handle case where step might not have any transitions yet
      max_sort_key = step.workflow_step_transitions.maximum(:sort_key) || 0

      # Create a new transition to pending state
      create(:workflow_step_transition,
             workflow_step: step,
             to_state: Tasker::Constants::WorkflowStepStatuses::PENDING,
             sort_key: max_sort_key + 1,
             most_recent: true)

      # Update previous transition to not be most recent
      step.workflow_step_transitions.where(most_recent: true)
          .where.not(id: step.workflow_step_transitions.last.id)
          .update_all(most_recent: false)
    end

    step
  end

  # Set step to in_progress (replacement for step.update!({ in_process: true }))
  def set_step_in_progress(step)
    step.state_machine.transition_to!(:in_progress)
    step.update_columns(in_process: true)
    step
  end

  # Force step to in_progress bypassing guards (for testing edge cases)
  # This simulates scenarios where a step gets into in_progress state outside normal workflow
  def force_step_in_progress(step)
    # Directly create transition without going through state machine guards
    # This is for testing edge cases where steps are in unexpected states
    max_sort_key = step.workflow_step_transitions.maximum(:sort_key) || 0

    create(:workflow_step_transition,
           workflow_step: step,
           to_state: Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS,
           sort_key: max_sort_key + 1,
           most_recent: true)

    # Update previous transition to not be most recent
    step.workflow_step_transitions.where(most_recent: true)
        .where.not(id: step.workflow_step_transitions.last.id)
        .update_all(most_recent: false)

    # Update the step columns to match
    step.update_columns(in_process: true)
    step
  end

  # Set step to cancelled (replacement for step.update!({ status: CANCELLED }))
  def set_step_cancelled(step)
    # Handle case where step might not have any transitions yet
    max_sort_key = step.workflow_step_transitions.maximum(:sort_key) || 0

    # Transition to cancelled state
    create(:workflow_step_transition,
           workflow_step: step,
           to_state: Tasker::Constants::WorkflowStepStatuses::CANCELLED,
           sort_key: max_sort_key + 1,
           most_recent: true)

    # Update previous transition to not be most recent
    step.workflow_step_transitions.where(most_recent: true)
        .where.not(id: step.workflow_step_transitions.last.id)
        .update_all(most_recent: false)

    step
  end

  # Set step to backoff state (replacement for step.update!({ backoff_request_seconds: 30, last_attempted_at: Time.zone.now }))
  def set_step_in_backoff(step, backoff_seconds = 30)
    step.update_columns(
      backoff_request_seconds: backoff_seconds,
      last_attempted_at: Time.zone.now
    )
    step
  end

  # Set step to error with max retries (replacement for complex error setup)
  def set_step_to_max_retries_error(step)
    step.state_machine.transition_to!(:in_progress)
    step.state_machine.transition_to!(:error)
    step.update_columns(
      attempts: step.retry_limit + 1,
      results: { error: 'Max retries reached' }
    )
    step
  end

  # Get sequence (temporary compatibility method for tests still using task_handler.get_sequence)
  def get_sequence_for_task(task)
    # Create a simple struct that provides access to steps and find_step_by_name
    # This maintains compatibility while we migrate away from sequence objects
    SequenceStruct.new(
      task.workflow_steps.includes(:named_step),
      task
    )
  end

  # Get viable steps (replacement for WorkflowStep.get_viable_steps)
  def get_viable_steps_for_task(task)
    sequence = get_sequence_for_task(task)
    Tasker::WorkflowStep.get_viable_steps(task, sequence)
  end
end

# Include in RSpec configuration
RSpec.configure do |config|
  config.include FactoryWorkflowHelpers
end
