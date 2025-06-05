# frozen_string_literal: true

require_relative '../concerns/idempotent_state_transitions'
require_relative '../concerns/event_publisher'
require_relative '../task_handler/step_group'
require_relative 'task_reenqueuer'

module Tasker
  module Orchestration
    # TaskFinalizer handles task completion and finalization logic
    #
    # This class provides implementation for task finalization while firing
    # lifecycle events for observability. Enhanced with TaskExecutionContext
    # integration for intelligent decision making.
    class TaskFinalizer
      include Tasker::Concerns::IdempotentStateTransitions
      include Tasker::Concerns::EventPublisher

      # Check if the task is blocked by errors
      #
      # @param task [Tasker::Task] The task to check
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @param processed_steps [Array<Tasker::WorkflowStep>] Recently processed steps
      # @return [Boolean] True if task is blocked by errors
      def blocked_by_errors?(task, _sequence, _processed_steps)
        # Use TaskExecutionContext for efficient decision making

        context = Tasker::TaskExecutionContext.find(task.task_id)
        is_blocked = context.execution_status == Constants::TaskExecution::ExecutionStatus::BLOCKED_BY_FAILURES

        if is_blocked
          Rails.logger.debug do
            "TaskFinalizer: Task #{task.task_id} is blocked - #{context.failed_steps} failed steps, #{context.ready_steps} ready steps"
          end

          Rails.logger.info("TaskFinalizer: Task #{task.task_id} blocked by #{context.failed_steps} failed steps (#{context.health_status} health)")
        end

        is_blocked
      rescue ActiveRecord::RecordNotFound
        # Fallback to original logic if context not available
        Rails.logger.warn("TaskFinalizer: TaskExecutionContext not found for task #{task.task_id}, using fallback logic")
        error_steps = task.workflow_steps.failed

        if error_steps.exists?
          Rails.logger.debug do
            "TaskFinalizer: Task #{task.task_id} is blocked by #{error_steps.count} error steps (fallback)"
          end
          Rails.logger.info("TaskFinalizer: Task #{task.task_id} blocked by #{error_steps.count} error steps: #{error_steps.joins(:named_step).pluck('tasker_named_steps.name')}")
          true
        else
          false
        end
      end

      # Finalize a task with processed steps
      #
      # @param task [Tasker::Task] The task to finalize
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @param processed_steps [Array<Tasker::WorkflowStep>] All processed steps
      def finalize_task_with_steps(task, _sequence, processed_steps)
        # Get execution context for richer event payload
        context = get_task_execution_context(task.task_id)

        # Fire finalization started event with context data
        publish_event(
          Constants::WorkflowEvents::TASK_FINALIZATION_STARTED,
          build_finalization_event_payload(task, context, processed_steps, :started)
        )

        # Use context-enhanced finalization logic with synchronous flag
        # Since this is called from task_handler.handle, we're in synchronous context
        finalize_task(task.task_id, synchronous: true)

        # Fire finalization completed event with final context
        final_context = get_task_execution_context(task.task_id)
        publish_event(
          Constants::WorkflowEvents::TASK_FINALIZATION_COMPLETED,
          build_finalization_event_payload(task, final_context, processed_steps, :completed)
        )
      end

      # Finalize a task based on its current state using TaskExecutionContext
      #
      # @param task_id [Integer] The task ID to finalize
      # @param synchronous [Boolean] Whether this is synchronous processing (default: false)
      def finalize_task(task_id, synchronous: false)
        task = Tasker::Task.find(task_id)
        context = get_task_execution_context(task_id)

        # Use TaskExecutionContext for intelligent decision making
        case context.execution_status
        when Constants::TaskExecution::ExecutionStatus::ALL_COMPLETE
          finalize_complete_task(task, context)
        when Constants::TaskExecution::ExecutionStatus::BLOCKED_BY_FAILURES
          finalize_error_task(task, context)
        when Constants::TaskExecution::ExecutionStatus::HAS_READY_STEPS,
             Constants::TaskExecution::ExecutionStatus::WAITING_FOR_DEPENDENCIES
          if synchronous
            # For synchronous processing, set to pending for later resumption
            finalize_pending_task(task, context)
          else
            # For asynchronous processing, re-enqueue for continued processing
            reenqueue_task_with_context(task, context)
          end
        when Constants::TaskExecution::ExecutionStatus::PROCESSING
          if synchronous
            # For synchronous processing, set to pending and wait for steps to complete
            finalize_pending_task(task, context,
                                  reason: Constants::TaskFinalization::PendingReasons::WAITING_FOR_STEP_COMPLETION)
          else
            # For asynchronous processing, re-enqueue to check later
            reenqueue_task_with_context(task, context,
                                        reason: Constants::TaskFinalization::ReenqueueReasons::STEPS_IN_PROGRESS)
          end
        else
          handle_unclear_task_state(task, context)
        end
      end

      # Handle no viable steps event
      #
      # Convenience method for event-driven workflows when no viable steps are found.
      # This triggers task finalization to determine next action.
      #
      # @param event [Hash] Event payload with task_id
      def handle_no_viable_steps(event)
        task_id = event[:task_id] || event
        finalize_task(task_id)
      end

      private

      # Get TaskExecutionContext with fallback handling
      #
      # @param task_id [Integer] The task ID
      # @return [Tasker::TaskExecutionContext, nil] The execution context or nil
      def get_task_execution_context(task_id)
        Tasker::TaskExecutionContext.find(task_id)
      rescue ActiveRecord::RecordNotFound
        Rails.logger.warn("TaskFinalizer: TaskExecutionContext not found for task #{task_id}")
        nil
      end

      # Framework Decision: Mark task as successfully completed
      #
      # @param task [Tasker::Task] The task to complete
      # @param context [Tasker::TaskExecutionContext] The execution context
      def finalize_complete_task(task, context)
        return unless safe_transition_to(task, Constants::TaskStatuses::COMPLETE)

        # Use clean API for task completion with context data
        publish_task_completed(
          task,
          completed_at: Time.current,
          completion_percentage: context&.completion_percentage,
          total_steps: context&.total_steps,
          health_status: context&.health_status
        )

        Rails.logger.info("TaskFinalizer: Task #{task.task_id} completed successfully (#{context&.total_steps} steps, #{context&.completion_percentage}% complete)")
      end

      # Framework Decision: Mark task as failed due to step errors
      #
      # @param task [Tasker::Task] The task to mark as failed
      # @param context [Tasker::TaskExecutionContext] The execution context
      def finalize_error_task(task, context)
        return unless safe_transition_to(task, Constants::TaskStatuses::ERROR)

        # Use clean API for task failure with context data
        publish_task_failed(
          task,
          error_message: Constants::TaskFinalization::ErrorMessages::STEPS_IN_ERROR_STATE,
          failed_steps_count: context&.failed_steps,
          completion_percentage: context&.completion_percentage,
          health_status: context&.health_status,
          total_steps: context&.total_steps
        )

        Rails.logger.info("TaskFinalizer: Task #{task.task_id} failed - #{context&.failed_steps} failed steps, #{context&.health_status} health")
      end

      # Framework Decision: Set task to pending for synchronous processing contexts
      #
      # This is used when we're in a synchronous processing context (like task_handler.handle)
      # and need to wait for currently running steps to complete before continuing.
      #
      # @param task [Tasker::Task] The task to set to pending
      # @param context [Tasker::TaskExecutionContext] The execution context
      # @param reason [String] Optional reason for setting to pending
      def finalize_pending_task(task, context, reason: nil)
        return unless safe_transition_to(task, Constants::TaskStatuses::PENDING)

        reason ||= determine_pending_reason(context)

        # Use clean API for task pending transition with context data
        publish_event(
          Constants::TaskEvents::INITIALIZE_REQUESTED,
          {
            task_id: task.task_id,
            task_name: task.name,
            reason: reason,
            ready_steps: context&.ready_steps,
            in_progress_steps: context&.in_progress_steps,
            completion_percentage: context&.completion_percentage,
            health_status: context&.health_status
          }
        )

        Rails.logger.info("TaskFinalizer: Task #{task.task_id} set to pending - #{reason} (ready_steps: #{context&.ready_steps}, in_progress: #{context&.in_progress_steps})")
      end

      # Framework Decision: Re-enqueue task for continued processing with context intelligence
      #
      # @param task [Tasker::Task] The task to re-enqueue
      # @param context [Tasker::TaskExecutionContext] The execution context
      # @param reason [String] Optional reason override
      def reenqueue_task_with_context(task, context, reason: nil)
        # Determine appropriate delay based on execution context
        delay_seconds = calculate_reenqueue_delay(context)
        reason ||= determine_reenqueue_reason(context)

        # Delegate to specialized TaskReenqueuer class with context-aware logic
        task_reenqueuer = Tasker::Orchestration::TaskReenqueuer.new

        if delay_seconds.positive?
          task_reenqueuer.reenqueue_task_delayed(
            task,
            delay_seconds: delay_seconds,
            reason: reason
          )
        else
          task_reenqueuer.reenqueue_task(task, reason: reason)
        end

        Rails.logger.info("TaskFinalizer: Task #{task.task_id} re-enqueued - #{reason} (delay: #{delay_seconds}s, ready_steps: #{context&.ready_steps})")
      end

      # Calculate intelligent re-enqueue delay based on execution context
      #
      # @param context [Tasker::TaskExecutionContext] The execution context
      # @return [Integer] Delay in seconds
      def calculate_reenqueue_delay(context)
        return 60 unless context # Default delay if no context

        case context.execution_status
        when Constants::TaskExecution::ExecutionStatus::PROCESSING
          # Steps actively running - check back soon
          30
        when Constants::TaskExecution::ExecutionStatus::WAITING_FOR_DEPENDENCIES
          # Dependencies might take time - longer delay
          300 # 5 minutes
        when Constants::TaskExecution::ExecutionStatus::HAS_READY_STEPS
          # Ready to process immediately
          0
        else
          60 # Default 1 minute
        end
      end

      # Determine context-aware re-enqueue reason
      #
      # @param context [Tasker::TaskExecutionContext] The execution context
      # @return [String] The reason for re-enqueueing
      def determine_reenqueue_reason(context)
        return Constants::TaskFinalization::ReenqueueReasons::CONTEXT_UNAVAILABLE unless context

        case context.execution_status
        when Constants::TaskExecution::ExecutionStatus::PROCESSING
          Constants::TaskFinalization::ReenqueueReasons::STEPS_IN_PROGRESS
        when Constants::TaskExecution::ExecutionStatus::WAITING_FOR_DEPENDENCIES
          Constants::TaskFinalization::ReenqueueReasons::AWAITING_DEPENDENCIES
        when Constants::TaskExecution::ExecutionStatus::HAS_READY_STEPS
          Constants::TaskFinalization::ReenqueueReasons::READY_STEPS_AVAILABLE
        else
          Constants::TaskFinalization::ReenqueueReasons::CONTINUING_WORKFLOW
        end
      end

      # Determine context-aware pending reason
      #
      # @param context [Tasker::TaskExecutionContext] The execution context
      # @return [String] The reason for setting to pending
      def determine_pending_reason(context)
        return Constants::TaskFinalization::PendingReasons::CONTEXT_UNAVAILABLE unless context

        case context.execution_status
        when Constants::TaskExecution::ExecutionStatus::PROCESSING
          Constants::TaskFinalization::PendingReasons::WAITING_FOR_STEP_COMPLETION
        when Constants::TaskExecution::ExecutionStatus::WAITING_FOR_DEPENDENCIES
          Constants::TaskFinalization::PendingReasons::WAITING_FOR_DEPENDENCIES
        when Constants::TaskExecution::ExecutionStatus::HAS_READY_STEPS
          Constants::TaskFinalization::PendingReasons::READY_FOR_PROCESSING
        else
          Constants::TaskFinalization::PendingReasons::WORKFLOW_PAUSED
        end
      end

      # Framework Decision: Handle unclear task state for investigation
      #
      # @param task [Tasker::Task] The task in unclear state
      # @param context [Tasker::TaskExecutionContext] The execution context
      def handle_unclear_task_state(task, context)
        if context
          Rails.logger.warn(
            "TaskFinalizer: Task #{task.task_id} in unclear state - " \
            "execution_status: #{context.execution_status}, " \
            "health_status: #{context.health_status}, " \
            "ready_steps: #{context.ready_steps}, " \
            "failed_steps: #{context.failed_steps}, " \
            "completion: #{context.completion_percentage}%"
          )

          # For unclear states with context, fire enhanced event for monitoring/alerting
          publish_event(
            Constants::WorkflowEvents::TASK_STATE_UNCLEAR,
            {
              task_id: task.task_id,
              execution_status: context.execution_status,
              health_status: context.health_status,
              recommended_action: context.recommended_action,
              workflow_summary: context.workflow_summary
            }
          )
        else
          # Fallback to original StepGroup logic if no context available
          Rails.logger.warn("TaskFinalizer: Task #{task.task_id} in unclear state - no execution context available, using fallback")
          sequence = get_sequence_for_task(task)
          step_group = Tasker::TaskHandler::StepGroup.build(task, sequence, [])
          debug_info = step_group.debug_state

          Rails.logger.warn(
            "TaskFinalizer: Task #{task.task_id} fallback state - " \
            "complete: #{debug_info[:is_complete]}, " \
            "pending: #{debug_info[:is_pending]}, " \
            "has_errors: #{debug_info[:has_errors]}"
          )

          publish_event(
            Constants::WorkflowEvents::TASK_STATE_UNCLEAR,
            {
              task_id: task.task_id,
              debug_state: debug_info,
              fallback_mode: true
            }
          )
        end
      end

      # Build rich event payload using TaskExecutionContext data
      #
      # @param task [Tasker::Task] The task
      # @param context [Tasker::TaskExecutionContext] The execution context
      # @param processed_steps [Array<Tasker::WorkflowStep>] Processed steps
      # @param event_phase [Symbol] :started or :completed
      # @return [Hash] Event payload
      def build_finalization_event_payload(task, context, processed_steps, event_phase)
        base_payload = {
          task_id: task.task_id,
          total_processed_steps: processed_steps.size,
          event_phase: event_phase
        }

        if context
          base_payload.merge({
                               execution_status: context.execution_status,
                               health_status: context.health_status,
                               completion_percentage: context.completion_percentage,
                               total_steps: context.total_steps,
                               ready_steps: context.ready_steps,
                               failed_steps: context.failed_steps,
                               recommended_action: context.recommended_action
                             })
        else
          base_payload.merge({
                               context_available: false,
                               final_status: event_phase == :completed ? task.reload.status : task.status
                             })
        end
      end

      # Get sequence for a task (fallback method)
      #
      # @param task [Tasker::Task] The task
      # @return [Tasker::Types::StepSequence] The step sequence
      def get_sequence_for_task(task)
        # Get task handler and use it to get sequence
        handler_factory = Tasker::HandlerFactory.instance
        task_handler = handler_factory.get(task.name)
        Tasker::Orchestration::StepSequenceFactory.get_sequence(task, task_handler)
      end
    end
  end
end
