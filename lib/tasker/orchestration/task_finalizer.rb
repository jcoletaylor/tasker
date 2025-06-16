# frozen_string_literal: true

require_relative '../concerns/idempotent_state_transitions'
require_relative '../concerns/event_publisher'
require_relative '../task_handler/step_group'
require_relative 'task_reenqueuer'
require_relative '../functions/function_based_task_execution_context'

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
      # @param _sequence [Tasker::Types::StepSequence] The step sequence (unused)
      # @param _processed_steps [Array<Tasker::WorkflowStep>] Recently processed steps (unused)
      # @return [Boolean] True if task is blocked by errors
      def blocked_by_errors?(task, _sequence, _processed_steps)
        BlockageChecker.blocked_by_errors?(task)
      end

      # Finalize a task with processed steps
      #
      # @param task [Tasker::Task] The task to finalize
      # @param _sequence [Tasker::Types::StepSequence] The step sequence (unused)
      # @param processed_steps [Array<Tasker::WorkflowStep>] All processed steps
      def finalize_task_with_steps(task, _sequence, processed_steps)
        FinalizationProcessor.finalize_with_steps(task, processed_steps, self)
      end

      # Finalize a task based on its current state using TaskExecutionContext
      #
      # @param task_id [Integer] The task ID to finalize
      # @param synchronous [Boolean] Whether this is synchronous processing (default: false)
      def finalize_task(task_id, synchronous: false)
        task = Tasker::Task.find(task_id)
        context = ContextManager.get_task_execution_context(task_id)

        FinalizationDecisionMaker.make_finalization_decision(task, context, synchronous, self)
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

      # Service method exposed for FinalizationDecisionMaker
      def complete_task(task, context)
        payload = {
          task: task,
          completed_at: Time.current,
          completion_percentage: context&.completion_percentage,
          total_steps: context&.total_steps,
          health_status: context&.health_status
        }

        # Ensure task is in in_progress state before transitioning to complete
        current_state = task.state_machine.current_state || Constants::TaskStatuses::PENDING

        Rails.logger.debug { "TaskFinalizer: Task #{task.task_id} current state is #{current_state}" }
        # If task is already complete, just publish the event
        if current_state == Constants::TaskStatuses::COMPLETE
          return unless task.update({ complete: true })

          publish_task_completed(**payload)
          return
        end

        # Handle task in error state - must go through pending first
        if current_state == Constants::TaskStatuses::ERROR
          return unless safe_transition_to(task, Constants::TaskStatuses::PENDING)

          Rails.logger.debug { "TaskFinalizer: Task #{task.task_id} transitioning from error to pending" }
          # Reset current state to pending for next transition
          # This is necessary because the state machine might not allow direct transition from error to complete
          # without going through pending first
          current_state = Constants::TaskStatuses::PENDING
        end

        # Ensure task is in in_progress state (transition only if not already there)
        if current_state != Constants::TaskStatuses::IN_PROGRESS && !safe_transition_to(task,
                                                                                        Constants::TaskStatuses::IN_PROGRESS)
          return
        end

        # Now transition to complete - always attempt this transition
        Rails.logger.debug { "TaskFinalizer: Task #{task.task_id} transitioning to complete" }
        ActiveRecord::Base.transaction do
          task.update!({ complete: true })
          unless safe_transition_to(task, Constants::TaskStatuses::COMPLETE)
            raise ActiveRecord::Rollback, "Failed to transition task #{task.task_id} to complete state"
          end
        end
        publish_task_completed(task, **payload)
        Rails.logger.info("TaskFinalizer: Task #{task.task_id} completed successfully (#{context&.total_steps} steps,
                            #{context&.completion_percentage}% complete)")
      end

      # Service method exposed for FinalizationDecisionMaker
      def error_task(task, context)
        return unless safe_transition_to(task, Constants::TaskStatuses::ERROR)

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

      # Service method exposed for FinalizationDecisionMaker
      def pending_task(task, context, reason: nil)
        return unless safe_transition_to(task, Constants::TaskStatuses::PENDING)

        reason ||= ReasonDeterminer.determine_pending_reason(context)

        publish_task_pending_transition(
          task,
          reason: reason,
          ready_steps: context&.ready_steps,
          in_progress_steps: context&.in_progress_steps,
          completion_percentage: context&.completion_percentage,
          health_status: context&.health_status
        )

        Rails.logger.info("TaskFinalizer: Task #{task.task_id} set to pending - #{reason} (ready_steps: #{context&.ready_steps}, in_progress: #{context&.in_progress_steps})")
      end

      # Service method exposed for FinalizationDecisionMaker
      def reenqueue_task_with_context(task, context, reason: nil)
        ReenqueueManager.reenqueue_with_context(task, context, reason)
      end

      # Service method exposed for event publishing
      def publish_finalization_started(task, processed_steps, context)
        publish_task_finalization_started(
          task,
          processed_steps_count: processed_steps.size,
          execution_status: context&.execution_status,
          health_status: context&.health_status,
          completion_percentage: context&.completion_percentage,
          total_steps: context&.total_steps,
          ready_steps: context&.ready_steps,
          failed_steps: context&.failed_steps,
          recommended_action: context&.recommended_action
        )
      end

      # Service method exposed for event publishing
      def publish_finalization_completed(task, processed_steps, context)
        publish_task_finalization_completed(
          task,
          processed_steps_count: processed_steps.size,
          execution_status: context&.execution_status,
          health_status: context&.health_status,
          completion_percentage: context&.completion_percentage,
          total_steps: context&.total_steps,
          ready_steps: context&.ready_steps,
          failed_steps: context&.failed_steps,
          recommended_action: context&.recommended_action
        )
      end

      # Service class to check task blockage by errors
      # Uses function-based implementation for reliable performance
      class BlockageChecker
        class << self
          # Check if the task is blocked by errors
          #
          # @param task [Tasker::Task] The task to check
          # @return [Boolean] True if task is blocked by errors
          def blocked_by_errors?(task)
            context = ContextManager.get_task_execution_context(task.task_id)

            # If no context is available, the task has no steps or doesn't exist
            # In either case, it's not blocked by errors
            return false unless context

            context.execution_status == Constants::TaskExecution::ExecutionStatus::BLOCKED_BY_FAILURES
          end
        end
      end

      # Service class to manage task execution context
      # Uses the new function-based implementations for reliable performance
      class ContextManager
        class << self
          # Get TaskExecutionContext using function-based implementation
          #
          # @param task_id [Integer] The task ID
          # @return [Tasker::Functions::FunctionBasedTaskExecutionContext, nil] The execution context or nil
          def get_task_execution_context(task_id)
            # Use our new function-based implementation - it should always return data or nil
            Tasker::Functions::FunctionBasedTaskExecutionContext.find(task_id)
          end
        end
      end

      # Service class to process finalization with steps
      # Reduces complexity by organizing step processing logic
      class FinalizationProcessor
        class << self
          # Finalize task with processed steps
          #
          # @param task [Tasker::Task] The task to finalize
          # @param processed_steps [Array<Tasker::WorkflowStep>] All processed steps
          # @param finalizer [TaskFinalizer] The finalizer instance for callbacks
          def finalize_with_steps(task, processed_steps, finalizer)
            context = ContextManager.get_task_execution_context(task.task_id)

            # Fire finalization started event
            finalizer.publish_finalization_started(task, processed_steps, context)

            # Use context-enhanced finalization logic with synchronous flag
            finalizer.finalize_task(task.task_id, synchronous: true)

            # Fire finalization completed event
            final_context = ContextManager.get_task_execution_context(task.task_id)
            finalizer.publish_finalization_completed(task, processed_steps, final_context)
          end
        end
      end

      # Service class to make finalization decisions
      # Reduces complexity by organizing decision-making logic
      class FinalizationDecisionMaker
        class << self
          # Make finalization decision based on task state
          #
          # @param task [Tasker::Task] The task to finalize
          # @param context [Tasker::TaskExecutionContext] The execution context
          # @param synchronous [Boolean] Whether this is synchronous processing
          # @param finalizer [TaskFinalizer] The finalizer instance for callbacks
          def make_finalization_decision(task, context, synchronous, finalizer)
            Rails.logger.info("TaskFinalizer: Making decision for task #{task.task_id} with execution_status: #{context&.execution_status}")

            # DEBUG: Log detailed context information
            if context
              Rails.logger.info("TaskFinalizer: Task #{task.task_id} context details - ready_steps: #{context.ready_steps}, total_steps: #{context.total_steps}, pending_steps: #{context.pending_steps}, in_progress_steps: #{context.in_progress_steps}, completed_steps: #{context.completed_steps}, failed_steps: #{context.failed_steps}")
            end

            # Handle nil context case
            unless context
              Rails.logger.info("TaskFinalizer: Task #{task.task_id} - no context available, handling as unclear state")
              UnclearStateHandler.handle(task, context, finalizer)
              return
            end

            case context.execution_status
            when Constants::TaskExecution::ExecutionStatus::ALL_COMPLETE
              Rails.logger.info("TaskFinalizer: Task #{task.task_id} - calling complete_task")
              finalizer.complete_task(task, context)
            when Constants::TaskExecution::ExecutionStatus::BLOCKED_BY_FAILURES
              Rails.logger.info("TaskFinalizer: Task #{task.task_id} - calling error_task")
              finalizer.error_task(task, context)
            when Constants::TaskExecution::ExecutionStatus::HAS_READY_STEPS
              Rails.logger.info("TaskFinalizer: Task #{task.task_id} - has ready steps, should execute them")
              handle_ready_steps_state(task, context, synchronous, finalizer)
            when Constants::TaskExecution::ExecutionStatus::WAITING_FOR_DEPENDENCIES
              Rails.logger.info("TaskFinalizer: Task #{task.task_id} - waiting for dependencies")
              handle_waiting_state(task, context, synchronous, finalizer)
            when Constants::TaskExecution::ExecutionStatus::PROCESSING
              Rails.logger.info("TaskFinalizer: Task #{task.task_id} - handling processing state")
              handle_processing_state(task, context, synchronous, finalizer)
            else
              Rails.logger.info("TaskFinalizer: Task #{task.task_id} - handling unclear state")
              UnclearStateHandler.handle(task, context, finalizer)
            end
          end

          private

          # Handle ready steps state - should execute the ready steps
          #
          # @param task [Tasker::Task] The task
          # @param context [Tasker::TaskExecutionContext] The execution context
          # @param synchronous [Boolean] Whether this is synchronous processing
          # @param finalizer [TaskFinalizer] The finalizer instance
          def handle_ready_steps_state(task, context, synchronous, finalizer)
            # When we have ready steps, we should execute them, not just wait
            # For now, transition task to in_progress and reenqueue for step execution
            Rails.logger.info("TaskFinalizer: Task #{task.task_id} has #{context.ready_steps} ready steps - transitioning to in_progress")

            # Transition task to in_progress to indicate work is happening
            current_state = task.state_machine.current_state
            unless [Constants::TaskStatuses::IN_PROGRESS, Constants::TaskStatuses::COMPLETE].include?(current_state)
              finalizer.safe_transition_to(task, Constants::TaskStatuses::IN_PROGRESS)
            end

            if synchronous
              # In synchronous mode, we can't actually execute steps here
              # The calling code should handle step execution
              Rails.logger.info("TaskFinalizer: Task #{task.task_id} ready for synchronous step execution")
            else
              # In asynchronous mode, reenqueue immediately for step execution
              finalizer.reenqueue_task_with_context(task, context,
                                                    reason: Constants::TaskFinalization::ReenqueueReasons::READY_STEPS_AVAILABLE)
            end
          end

          # Handle waiting for dependencies state
          #
          # @param task [Tasker::Task] The task
          # @param context [Tasker::TaskExecutionContext] The execution context
          # @param synchronous [Boolean] Whether this is synchronous processing
          # @param finalizer [TaskFinalizer] The finalizer instance
          def handle_waiting_state(task, context, synchronous, finalizer)
            if synchronous
              finalizer.pending_task(task, context,
                                     reason: Constants::TaskFinalization::PendingReasons::WAITING_FOR_DEPENDENCIES)
            else
              finalizer.reenqueue_task_with_context(task, context,
                                                    reason: Constants::TaskFinalization::ReenqueueReasons::AWAITING_DEPENDENCIES)
            end
          end

          # Handle processing state
          #
          # @param task [Tasker::Task] The task
          # @param context [Tasker::TaskExecutionContext] The execution context
          # @param synchronous [Boolean] Whether this is synchronous processing
          # @param finalizer [TaskFinalizer] The finalizer instance
          def handle_processing_state(task, context, synchronous, finalizer)
            if synchronous
              finalizer.pending_task(task, context,
                                     reason: Constants::TaskFinalization::PendingReasons::WAITING_FOR_STEP_COMPLETION)
            else
              finalizer.reenqueue_task_with_context(task, context,
                                                    reason: Constants::TaskFinalization::ReenqueueReasons::STEPS_IN_PROGRESS)
            end
          end
        end
      end

      # Service class to determine reasons for pending/reenqueue
      # Reduces complexity by organizing reason determination logic
      class ReasonDeterminer
        # Frozen hash for O(1) pending reason lookups
        PENDING_REASON_MAP = {
          Constants::TaskExecution::ExecutionStatus::HAS_READY_STEPS =>
            Constants::TaskFinalization::PendingReasons::READY_FOR_PROCESSING,
          Constants::TaskExecution::ExecutionStatus::WAITING_FOR_DEPENDENCIES =>
            Constants::TaskFinalization::PendingReasons::WAITING_FOR_DEPENDENCIES,
          Constants::TaskExecution::ExecutionStatus::PROCESSING =>
            Constants::TaskFinalization::PendingReasons::WAITING_FOR_STEP_COMPLETION
        }.freeze

        # Frozen hash for O(1) reenqueue reason lookups
        REENQUEUE_REASON_MAP = {
          Constants::TaskExecution::ExecutionStatus::HAS_READY_STEPS =>
            Constants::TaskFinalization::ReenqueueReasons::READY_STEPS_AVAILABLE,
          Constants::TaskExecution::ExecutionStatus::WAITING_FOR_DEPENDENCIES =>
            Constants::TaskFinalization::ReenqueueReasons::AWAITING_DEPENDENCIES,
          Constants::TaskExecution::ExecutionStatus::PROCESSING =>
            Constants::TaskFinalization::ReenqueueReasons::STEPS_IN_PROGRESS
        }.freeze

        class << self
          # Determine reason for pending state
          #
          # @param context [Tasker::TaskExecutionContext] The execution context
          # @return [String] The pending reason
          def determine_pending_reason(context)
            return Constants::TaskFinalization::PendingReasons::CONTEXT_UNAVAILABLE unless context

            PENDING_REASON_MAP.fetch(
              context.execution_status,
              Constants::TaskFinalization::PendingReasons::WORKFLOW_PAUSED
            )
          end

          # Determine reason for reenqueue
          #
          # @param context [Tasker::TaskExecutionContext] The execution context
          # @return [String] The reenqueue reason
          def determine_reenqueue_reason(context)
            return Constants::TaskFinalization::ReenqueueReasons::CONTEXT_UNAVAILABLE unless context

            REENQUEUE_REASON_MAP.fetch(
              context.execution_status,
              Constants::TaskFinalization::ReenqueueReasons::CONTINUING_WORKFLOW
            )
          end
        end
      end

      # Service class to manage task reenqueuing
      # Reduces complexity by organizing reenqueue logic
      class ReenqueueManager
        class << self
          # Re-enqueue task with context intelligence
          #
          # @param task [Tasker::Task] The task to re-enqueue
          # @param context [Tasker::TaskExecutionContext] The execution context
          # @param reason [String] Optional reason override
          def reenqueue_with_context(task, context, reason)
            delay_seconds = DelayCalculator.calculate_reenqueue_delay(context)
            reason ||= ReasonDeterminer.determine_reenqueue_reason(context)

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
        end
      end

      # Service class to calculate delays
      # Reduces complexity by organizing delay calculation logic
      class DelayCalculator
        # Frozen hash for O(1) delay lookups with descriptive comments
        DELAY_MAP = {
          Constants::TaskExecution::ExecutionStatus::HAS_READY_STEPS => 0, # Steps ready - immediate processing
          Constants::TaskExecution::ExecutionStatus::WAITING_FOR_DEPENDENCIES => 300, # Waiting for deps - 5 minutes
          Constants::TaskExecution::ExecutionStatus::PROCESSING => 30 # Processing - moderate delay
        }.freeze

        DEFAULT_DELAY = 60 # Default delay for unclear states or no context

        class << self
          # Calculate intelligent re-enqueue delay based on execution context and step backoff timing
          #
          # This method considers the actual backoff timing of failed steps to avoid
          # reenqueuing tasks before any steps are ready for retry.
          #
          # @param context [Tasker::TaskExecutionContext] The execution context
          # @return [Integer] Delay in seconds
          def calculate_reenqueue_delay(context)
            return DEFAULT_DELAY unless context

            # For waiting_for_dependencies status, check if we have failed steps with backoff timing
            if context.execution_status == Constants::TaskExecution::ExecutionStatus::WAITING_FOR_DEPENDENCIES
              optimal_delay = calculate_optimal_backoff_delay(context.task_id)
              return optimal_delay if optimal_delay.positive?
            end

            DELAY_MAP.fetch(context.execution_status, DEFAULT_DELAY)
          end

          private

          # Calculate optimal delay based on step backoff timing
          #
          # Finds the step with the longest remaining backoff time and schedules
          # the task to be reenqueued when that step becomes ready for retry.
          #
          # @param task_id [Integer] The task ID
          # @return [Integer] Optimal delay in seconds, or 0 if no backoff needed
          def calculate_optimal_backoff_delay(task_id)
            # Get step readiness status for all steps in the task
            step_statuses = Tasker::StepReadinessStatus.for_task(task_id)

            # Find failed steps that have backoff timing, regardless of retry_eligible status
            # This is because retry_eligible can be false due to timing, but we still want
            # to schedule based on when the step will become retry-eligible
            failed_steps_with_backoff = step_statuses.select do |step_status|
              step_status.current_state == 'error' &&
                !step_status.ready_for_execution &&
                step_status.next_retry_at.present?
            end

            return 0 if failed_steps_with_backoff.empty?

            # Find the step with the longest remaining backoff time
            now = Time.current
            max_delay = failed_steps_with_backoff.map do |step_status|
              next_retry_time = step_status.next_retry_at
              next_retry_time > now ? (next_retry_time - now).to_i : 0
            end.max

            # Add a small buffer (5 seconds) to ensure the step is definitely ready
            # Cap the maximum delay at 30 minutes to prevent excessive delays
            [(max_delay || 0) + 5, 1800].min
          end
        end
      end

      # Service class to handle unclear task states
      # Reduces complexity by organizing unclear state handling logic
      class UnclearStateHandler
        class << self
          # Handle unclear task state
          #
          # @param task [Tasker::Task] The task
          # @param context [Tasker::TaskExecutionContext] The execution context
          # @param finalizer [TaskFinalizer] The finalizer instance
          def handle(task, context, finalizer)
            if context
              Rails.logger.warn do
                "TaskFinalizer: Task #{task.task_id} in unclear state: " \
                  "execution_status=#{context.execution_status}, " \
                  "health_status=#{context.health_status}, " \
                  "ready_steps=#{context.ready_steps}, " \
                  "failed_steps=#{context.failed_steps}, " \
                  "in_progress_steps=#{context.in_progress_steps}"
              end

              # Default to re-enqueuing with a longer delay for unclear states
              finalizer.reenqueue_task_with_context(
                task,
                context,
                reason: Constants::TaskFinalization::ReenqueueReasons::CONTINUING_WORKFLOW
              )
            else
              Rails.logger.error("TaskFinalizer: Task #{task.task_id} has no execution context and unclear state")

              # Without context, attempt to transition to error state
              finalizer.error_task(
                task,
                nil # No context available
              )
            end
          end
        end
      end
    end
  end
end
