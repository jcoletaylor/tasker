# frozen_string_literal: true

require 'dry/events'

module Tasker
  module Orchestration
    # TaskFinalizer handles task completion and finalization logic
    #
    # This class extracts the finalization logic from TaskHandler::InstanceMethods
    # and makes it event-driven, responding to workflow completion events.
    class TaskFinalizer
      include Dry::Events::Publisher[:task_finalizer]
      include Tasker::Concerns::IdempotentStateTransitions

      # Register events that this component publishes
      register_event(Tasker::Constants::WorkflowEvents::TASK_FINALIZATION_STARTED)
      register_event(Tasker::Constants::WorkflowEvents::TASK_FINALIZATION_COMPLETED)
      register_event(Tasker::Constants::WorkflowEvents::TASK_REENQUEUE_REQUESTED)

      class << self
        # Subscribe to workflow events for task finalization
        #
        # @param bus [Tasker::Events::Bus] The event bus to subscribe to
        def subscribe_to_workflow_events(bus = nil)
          event_bus = bus || Tasker::LifecycleEvents.bus
          finalizer = new

          # Subscribe to no viable steps events (main trigger for finalization)
          event_bus.subscribe(Tasker::Constants::WorkflowEvents::NO_VIABLE_STEPS) do |event|
            finalizer.finalize_task(event[:task_id])
          end

          # Subscribe to step execution completion for potential early finalization
          event_bus.subscribe(Tasker::Constants::WorkflowEvents::STEPS_EXECUTION_COMPLETED) do |event|
            finalizer.check_task_completion(event[:task_id])
          end

          Rails.logger.info('Tasker::Orchestration::TaskFinalizer subscribed to workflow events')
        end

        # Compatibility method for TaskRunnerJob cleanup
        # TODO: Remove this once we eliminate the old reenqueue tracking entirely
        def complete_reenqueue(task_id)
          # No-op for now, kept for compatibility
        end
      end

      # Finalize a task when no more viable steps are found
      #
      # @param task_id [Integer] The task ID to finalize
      # @return [Symbol] :reenqueued, :completed, :error, or :blocked to indicate terminal action
      def finalize_task(task_id)
        task = Tasker::Task.find(task_id)

        Rails.logger.debug { "TaskFinalizer: Finalizing task #{task_id}" }

        publish(Tasker::Constants::WorkflowEvents::TASK_FINALIZATION_STARTED, {
                  task_id: task_id,
                  task_name: task.name,
                  started_at: Time.current
                })

        # Also publish to main LifecycleEvents bus
        Tasker::LifecycleEvents.fire(
          Tasker::Constants::WorkflowEvents::TASK_FINALIZATION_STARTED,
          {
            task_id: task_id,
            task_name: task.name,
            started_at: Time.current
          }
        )

        # Check if task is blocked by errors first
        error_result = check_task_blocked_by_errors(task)
        if error_result == :reenqueued || error_result == :blocked
          # Task was reenqueued or blocked - this is a terminal action
          return error_result
        end

        # Analyze step completion state
        step_analysis = analyze_step_completion(task)

        result = case step_analysis[:state]
        when :complete
          complete_task(task)
          :completed
        when :pending
          reenqueue_task(task)
        else
          # Default to complete if we can't determine state clearly
          complete_task(task)
          :completed
        end

        publish(Tasker::Constants::WorkflowEvents::TASK_FINALIZATION_COMPLETED, {
                  task_id: task_id,
                  final_state: task.status,
                  finalization_result: result,
                  completed_at: Time.current
                })

        # Also publish to main LifecycleEvents bus
        Tasker::LifecycleEvents.fire(
          Tasker::Constants::WorkflowEvents::TASK_FINALIZATION_COMPLETED,
          {
            task_id: task_id,
            final_state: task.status,
            finalization_result: result,
            completed_at: Time.current
          }
        )

        result
      rescue StandardError => e
        Rails.logger.error { "TaskFinalizer: Error finalizing task #{task_id}: #{e.message}" }
        :error
      end

      # Check if a task might be ready for completion without waiting for no viable steps
      #
      # @param task_id [Integer] The task ID to check
      # @return [Symbol] :reenqueued, :completed, or :no_action
      def check_task_completion(task_id)
        task = Tasker::Task.find(task_id)

        # Only check if task is in progress
        return :no_action unless task.status == Constants::TaskStatuses::IN_PROGRESS

        step_analysis = analyze_step_completion(task)

        # If all steps are complete, trigger finalization
        return :no_action unless step_analysis[:state] == :complete

        Rails.logger.debug { "TaskFinalizer: Task #{task_id} appears complete, triggering finalization" }
        finalize_task(task_id)
      end

      private

      # Check if task is blocked by unrecoverable errors
      #
      # @param task [Tasker::Task] The task to check
      # @return [Symbol] :reenqueued, :blocked, or :continue
      def check_task_blocked_by_errors(task)
        error_steps = task.workflow_steps.select { |step| step_in_error?(step) }

        return :continue if error_steps.empty?

        # Check if any error steps have exceeded retry limits
        unrecoverable_steps = error_steps.select do |step|
          step.attempts >= step.retry_limit || !step.retryable
        end

        if unrecoverable_steps.any?
          Rails.logger.debug { "TaskFinalizer: Task #{task.task_id} has unrecoverable step errors" }

          # Use the concern's safe_transition_to method
          safe_transition_to(task, Constants::TaskStatuses::ERROR)

          # Fire error event
          Tasker::LifecycleEvents.fire(
            Tasker::Constants::TaskEvents::FAILED,
            {
              task_id: task.task_id,
              task_name: task.name,
              error_steps: unrecoverable_steps.map(&:name).join(', '),
              error_step_results: unrecoverable_steps.map do |step|
                { step_id: step.workflow_step_id, step_name: step.name, step_results: step.results }
              end
            }
          )

          return :blocked
        end

        # Error steps are recoverable, transition back to pending for retry
        safe_transition_to(task, Constants::TaskStatuses::PENDING)

        # Reenqueue for retry - this should be terminal
        return reenqueue_task(task)
      end

      # Complete a task successfully
      #
      # @param task [Tasker::Task] The task to complete
      def complete_task(task)
        Rails.logger.debug { "TaskFinalizer: Completing task #{task.task_id}" }

        # Use the concern's safe_transition_to method
        safe_transition_to(task, Constants::TaskStatuses::COMPLETE)

        # Fire completion event
        Tasker::LifecycleEvents.fire(
          Tasker::Constants::TaskEvents::COMPLETED,
          { task_id: task.task_id, task_name: task.name }
        )
      end

      # Re-enqueue a task for further processing
      #
      # This is the TERMINAL action - once a task is reenqueued,
      # the current execution path should stop.
      #
      # @param task [Tasker::Task] The task to re-enqueue
      # @return [Symbol] :reenqueued (always, as this is terminal)
      def reenqueue_task(task)
        Rails.logger.debug { "TaskFinalizer: Re-enqueuing task #{task.task_id} (TERMINAL ACTION)" }

        # Transition to pending state for reenqueue
        safe_transition_to(task, Constants::TaskStatuses::PENDING)

        # Publish reenqueue event
        publish(Tasker::Constants::WorkflowEvents::TASK_REENQUEUE_REQUESTED, {
                  task_id: task.task_id,
                  task_name: task.name,
                  reenqueued_at: Time.current
                })

        # Fire observability event
        Tasker::LifecycleEvents.fire(
          Tasker::Constants::ObservabilityEvents::Task::ENQUEUE,
          { task_id: task.task_id, task_name: task.name, task_context: task.context }
        )

        # Schedule the background job - this is the terminal action
        Tasker::TaskRunnerJob.perform_later(task.task_id)

        Rails.logger.debug { "TaskFinalizer: Task #{task.task_id} successfully reenqueued, execution complete" }

        # Return terminal status - caller should stop processing
        :reenqueued
      end

      # Analyze the completion state of all steps in a task
      #
      # @param task [Tasker::Task] The task to analyze
      # @return [Hash] Analysis results with state and details
      def analyze_step_completion(task)
        steps = task.workflow_steps.includes(:named_step, :parents, :children)

        # Categorize steps by status
        complete_steps = steps.select { |step| step_complete?(step) }
        pending_steps = steps.select { |step| step_pending_or_ready?(step) }
        error_steps = steps.select { |step| step_in_error?(step) }
        in_progress_steps = steps.select { |step| step_in_progress?(step) }

        total_steps = steps.count

        Rails.logger.debug do
          "TaskFinalizer: Step analysis for task #{task.task_id}: " \
            "#{complete_steps.count}/#{total_steps} complete, " \
            "#{pending_steps.count} pending, " \
            "#{error_steps.count} error, " \
            "#{in_progress_steps.count} in progress"
        end

        # Determine overall state
        if complete_steps.count == total_steps
          { state: :complete, details: 'All steps complete' }
        elsif pending_steps.any? || in_progress_steps.any?
          { state: :pending, details: 'Steps still pending or in progress' }
        elsif error_steps.any?
          { state: :error, details: 'Steps in error state' }
        else
          { state: :complete, details: 'No actionable steps remaining' }
        end
      end

      # Check if a step is complete
      #
      # @param step [WorkflowStep] The step to check
      # @return [Boolean] True if step is complete
      def step_complete?(step)
        [
          Constants::WorkflowStepStatuses::COMPLETE,
          Constants::WorkflowStepStatuses::RESOLVED_MANUALLY
        ].include?(step.status)
      end

      # Check if a step is pending or ready for execution
      #
      # @param step [WorkflowStep] The step to check
      # @return [Boolean] True if step is pending or ready
      def step_pending_or_ready?(step)
        step.status == Constants::WorkflowStepStatuses::PENDING && !step.processed
      end

      # Check if a step is in error state
      #
      # @param step [WorkflowStep] The step to check
      # @return [Boolean] True if step is in error
      def step_in_error?(step)
        step.status == Constants::WorkflowStepStatuses::ERROR
      end

      # Check if a step is currently in progress
      #
      # @param step [WorkflowStep] The step to check
      # @return [Boolean] True if step is in progress
      def step_in_progress?(step)
        step.status == Constants::WorkflowStepStatuses::IN_PROGRESS
      end
    end
  end
end
