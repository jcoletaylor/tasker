# typed: false
# frozen_string_literal: true

module Tasker
  # Constants used throughout the Tasker gem
  #
  # This module contains constants for workflow step and task statuses,
  # validation states, and configuration schemas.
  module Constants
    # Status values for workflow steps
    module WorkflowStepStatuses
      # Step is waiting to be processed
      PENDING = 'pending'
      # Step is currently being processed
      IN_PROGRESS = 'in_progress'
      # Step encountered an error during processing
      ERROR = 'error'
      # Step completed successfully
      COMPLETE = 'complete'
      # Step was manually marked as resolved
      RESOLVED_MANUALLY = 'resolved_manually'
      # Step was cancelled
      CANCELLED = 'cancelled'
    end

    # Status values for tasks
    module TaskStatuses
      # Task is waiting to be processed
      PENDING = 'pending'
      # Task is currently being processed
      IN_PROGRESS = 'in_progress'
      # Task encountered an error during processing
      ERROR = 'error'
      # Task completed successfully
      COMPLETE = 'complete'
      # Task was manually marked as resolved
      RESOLVED_MANUALLY = 'resolved_manually'
      # Task was cancelled
      CANCELLED = 'cancelled'
    end

    # All valid status values for workflow steps
    VALID_WORKFLOW_STEP_STATUSES = [
      WorkflowStepStatuses::PENDING,
      WorkflowStepStatuses::IN_PROGRESS,
      WorkflowStepStatuses::ERROR,
      WorkflowStepStatuses::COMPLETE,
      WorkflowStepStatuses::CANCELLED,
      WorkflowStepStatuses::RESOLVED_MANUALLY
    ].freeze

    # Status values for steps that are not ready to be processed
    UNREADY_WORKFLOW_STEP_STATUSES = [
      WorkflowStepStatuses::IN_PROGRESS,
      WorkflowStepStatuses::COMPLETE,
      WorkflowStepStatuses::CANCELLED,
      WorkflowStepStatuses::RESOLVED_MANUALLY
    ].freeze

    # All valid status values for tasks
    VALID_TASK_STATUSES = [
      TaskStatuses::PENDING,
      TaskStatuses::IN_PROGRESS,
      TaskStatuses::ERROR,
      TaskStatuses::COMPLETE,
      TaskStatuses::CANCELLED,
      TaskStatuses::RESOLVED_MANUALLY
    ].freeze

    # Step status values that indicate completion (success or otherwise)
    VALID_STEP_COMPLETION_STATES = [
      WorkflowStepStatuses::COMPLETE,
      WorkflowStepStatuses::RESOLVED_MANUALLY,
      WorkflowStepStatuses::CANCELLED
    ].freeze

    # Step status values that indicate the step is still in a working state
    VALID_STEP_STILL_WORKING_STATES = [WorkflowStepStatuses::PENDING, WorkflowStepStatuses::IN_PROGRESS].freeze

    # Default value for unknown identifiers
    UNKNOWN = 'unknown'

    # JSON schema for validating task handler YAML configurations
    YAML_SCHEMA = {
      type: 'object',
      required: %w[name task_handler_class step_templates],
      properties: {
        name: { type: 'string' },
        module_namespace: { type: 'string', default: nil },
        task_handler_class: { type: 'string' },
        concurrent: { type: 'boolean', default: true },
        default_dependent_system: { type: 'string' },
        named_steps: {
          type: 'array',
          items: { type: 'string' }
        },
        schema: { type: 'object' },
        step_templates: {
          type: 'array',
          items: {
            type: 'object',
            required: %w[name handler_class],
            properties: {
              dependent_system: { type: 'string' },
              name: { type: 'string' },
              description: { type: 'string' },
              default_retryable: { type: 'boolean' },
              default_retry_limit: { type: 'integer' },
              skippable: { type: 'boolean' },
              handler_class: { type: 'string' },
              depends_on_step: { type: 'string' },
              depends_on_steps: {
                type: 'array',
                items: { type: 'string' }
              },
              handler_config: { type: 'object' }
            }
          }
        },
        environments: {
          type: 'object',
          additionalProperties: {
            type: 'object',
            properties: {
              step_templates: {
                type: 'array',
                items: {
                  type: 'object',
                  required: %w[name],
                  properties: {
                    name: { type: 'string' },
                    handler_config: { type: 'object' }
                  }
                }
              }
            }
          }
        }
      }
    }.freeze

    # Event names for task state transitions
    module TaskEvents
      # Task is being initialized
      INITIALIZE_REQUESTED = 'task.initialize_requested'
      # Task is starting execution
      START_REQUESTED = 'task.start_requested'
      # Task has completed successfully
      COMPLETED = 'task.completed'
      # Task has failed with an error
      FAILED = 'task.failed'
      # Task is being retried after an error
      RETRY_REQUESTED = 'task.retry_requested'
      # Task was manually resolved
      RESOLVED_MANUALLY = 'task.resolved_manually'
      # Task was cancelled
      CANCELLED = 'task.cancelled'
      # Before any task state transition
      BEFORE_TRANSITION = 'task.before_transition'
    end

    # Event names for workflow step state transitions
    module StepEvents
      # Step is being initialized
      INITIALIZE_REQUESTED = 'step.initialize_requested'
      # Step execution is being requested
      EXECUTION_REQUESTED = 'step.execution_requested'
      # Before step handling begins
      BEFORE_HANDLE = 'step.before_handle'
      # Step is being handled/processed
      HANDLE = 'step.handle'
      # Step has completed successfully
      COMPLETED = 'step.completed'
      # Step has failed with an error
      FAILED = 'step.failed'
      # Step is being retried after an error
      RETRY_REQUESTED = 'step.retry_requested'
      # Step was manually resolved
      RESOLVED_MANUALLY = 'step.resolved_manually'
      # Step was cancelled
      CANCELLED = 'step.cancelled'
      # Before any step state transition
      BEFORE_TRANSITION = 'step.before_transition'
    end

    # All valid task event names
    VALID_TASK_EVENTS = [
      TaskEvents::INITIALIZE_REQUESTED,
      TaskEvents::START_REQUESTED,
      TaskEvents::COMPLETED,
      TaskEvents::FAILED,
      TaskEvents::RETRY_REQUESTED,
      TaskEvents::RESOLVED_MANUALLY,
      TaskEvents::CANCELLED,
      TaskEvents::BEFORE_TRANSITION
    ].freeze

    # All valid step event names
    VALID_STEP_EVENTS = [
      StepEvents::INITIALIZE_REQUESTED,
      StepEvents::EXECUTION_REQUESTED,
      StepEvents::BEFORE_HANDLE,
      StepEvents::HANDLE,
      StepEvents::COMPLETED,
      StepEvents::FAILED,
      StepEvents::RETRY_REQUESTED,
      StepEvents::RESOLVED_MANUALLY,
      StepEvents::CANCELLED,
      StepEvents::BEFORE_TRANSITION
    ].freeze

    # Event categories for observability, telemetry, and process tracking
    # These events provide visibility into workflow execution for monitoring purposes
    module ObservabilityEvents
      # Task-level observability events
      module Task
        # Fired when task handler begins processing a task
        HANDLE = 'task.handle'
        # Fired when a task is enqueued for processing
        ENQUEUE = 'task.enqueue'
        # Fired when task processing is finalized
        FINALIZE = 'task.finalize'
      end

      # Step-level observability events
      module Step
        # Fired during viable step discovery process
        FIND_VIABLE = 'step.find_viable'
        # Fired when step handler begins processing a step
        HANDLE = 'step.handle'
        # Fired when step execution is delayed due to backoff
        BACKOFF = 'step.backoff'
        # Fired when a step is skipped during processing
        SKIP = 'step.skip'
        # Fired when a step reaches maximum retry attempts
        MAX_RETRIES_REACHED = 'step.max_retries_reached'
      end
    end

    # Workflow orchestration events (for event-driven workflow coordination)
    # These events coordinate workflow execution between components
    module WorkflowEvents
      # Task orchestration events
      TASK_STARTED = 'workflow.task_started'
      TASK_COMPLETED = 'workflow.task_completed'
      TASK_FAILED = 'workflow.task_failed'
      TASK_FINALIZATION_STARTED = 'workflow.task_finalization_started'
      TASK_FINALIZATION_COMPLETED = 'workflow.task_finalization_completed'
      TASK_REENQUEUE_STARTED = 'workflow.task_reenqueue_started'
      TASK_REENQUEUE_REQUESTED = 'workflow.task_reenqueue_requested'
      TASK_REENQUEUE_FAILED = 'workflow.task_reenqueue_failed'
      TASK_REENQUEUE_DELAYED = 'workflow.task_reenqueue_delayed'
      TASK_STATE_UNCLEAR = 'workflow.task_state_unclear'

      # Step orchestration events
      STEP_COMPLETED = 'workflow.step_completed'
      STEP_FAILED = 'workflow.step_failed'
      STEP_EXECUTION_FAILED = 'workflow.step_execution_failed'
      VIABLE_STEPS_DISCOVERED = 'workflow.viable_steps_discovered'
      VIABLE_STEPS_BATCH_READY = 'workflow.viable_steps_batch_ready'
      STEPS_EXECUTION_STARTED = 'workflow.steps_execution_started'
      STEPS_EXECUTION_COMPLETED = 'workflow.steps_execution_completed'
      NO_VIABLE_STEPS = 'workflow.no_viable_steps'

      # Orchestration control events
      ORCHESTRATION_REQUESTED = 'workflow.orchestration_requested'
    end

    # All event constants for easy access and validation
    ALL_EVENTS = [
      # Task state events
      TaskEvents::INITIALIZE_REQUESTED,
      TaskEvents::START_REQUESTED,
      TaskEvents::COMPLETED,
      TaskEvents::FAILED,
      TaskEvents::RETRY_REQUESTED,
      TaskEvents::RESOLVED_MANUALLY,
      TaskEvents::CANCELLED,
      TaskEvents::BEFORE_TRANSITION,

      # Step state events
      StepEvents::INITIALIZE_REQUESTED,
      StepEvents::EXECUTION_REQUESTED,
      StepEvents::BEFORE_HANDLE,
      StepEvents::HANDLE,
      StepEvents::COMPLETED,
      StepEvents::FAILED,
      StepEvents::RETRY_REQUESTED,
      StepEvents::RESOLVED_MANUALLY,
      StepEvents::CANCELLED,
      StepEvents::BEFORE_TRANSITION,

      # Workflow orchestration events
      WorkflowEvents::ORCHESTRATION_REQUESTED,
      WorkflowEvents::TASK_STARTED,
      WorkflowEvents::STEP_COMPLETED,
      WorkflowEvents::VIABLE_STEPS_DISCOVERED,
      WorkflowEvents::NO_VIABLE_STEPS,
      WorkflowEvents::VIABLE_STEPS_BATCH_READY,

      # Observability/process tracking events
      ObservabilityEvents::Task::HANDLE,
      ObservabilityEvents::Task::ENQUEUE,
      ObservabilityEvents::Task::FINALIZE,

      # Step observability events
      ObservabilityEvents::Step::FIND_VIABLE,
      ObservabilityEvents::Step::HANDLE,
      ObservabilityEvents::Step::BACKOFF,
      ObservabilityEvents::Step::SKIP,
      ObservabilityEvents::Step::MAX_RETRIES_REACHED
    ].freeze

    # Test events for testing infrastructure
    module TestEvents
      BASIC_EVENT = 'test.event'
      SLOW_EVENT = 'Slow.Event'
      TEST_EVENT = 'Test.Event'
    end

    # All valid workflow orchestration events
    VALID_WORKFLOW_EVENTS = [
      WorkflowEvents::TASK_STARTED,
      WorkflowEvents::TASK_COMPLETED,
      WorkflowEvents::TASK_FAILED,
      WorkflowEvents::TASK_FINALIZATION_STARTED,
      WorkflowEvents::TASK_FINALIZATION_COMPLETED,
      WorkflowEvents::TASK_REENQUEUE_STARTED,
      WorkflowEvents::TASK_REENQUEUE_REQUESTED,
      WorkflowEvents::TASK_REENQUEUE_FAILED,
      WorkflowEvents::TASK_REENQUEUE_DELAYED,
      WorkflowEvents::TASK_STATE_UNCLEAR,
      WorkflowEvents::STEP_COMPLETED,
      WorkflowEvents::STEP_FAILED,
      WorkflowEvents::STEP_EXECUTION_FAILED,
      WorkflowEvents::VIABLE_STEPS_DISCOVERED,
      WorkflowEvents::VIABLE_STEPS_BATCH_READY,
      WorkflowEvents::STEPS_EXECUTION_STARTED,
      WorkflowEvents::STEPS_EXECUTION_COMPLETED,
      WorkflowEvents::NO_VIABLE_STEPS,
      WorkflowEvents::ORCHESTRATION_REQUESTED
    ].freeze

    # All valid test events
    VALID_TEST_EVENTS = [
      TestEvents::BASIC_EVENT,
      TestEvents::SLOW_EVENT,
      TestEvents::TEST_EVENT
    ].freeze
  end
end
