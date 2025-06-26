# frozen_string_literal: true

module Tasker
  module Orchestration
    # WorkflowCoordinator handles the main task execution loop
    #
    # This coordinator extracts the proven loop-based execution logic from TaskHandler
    # and provides a strategy pattern for composition with different reenqueuer strategies.
    # This enables proper testing of the complete workflow execution path.
    #
    # Enhanced with structured logging and performance monitoring for production observability.
    class WorkflowCoordinator
      include Tasker::Concerns::StructuredLogging
      include Tasker::Concerns::EventPublisher

      attr_reader :reenqueuer_strategy

      # Initialize coordinator with reenqueuer strategy
      #
      # @param reenqueuer_strategy [Object] Strategy for handling task reenqueuing
      def initialize(reenqueuer_strategy: nil)
        @reenqueuer_strategy = reenqueuer_strategy || default_reenqueuer_strategy
      end

      # Execute the complete workflow for a task
      #
      # This method contains the proven loop logic extracted from TaskHandler#handle
      # and delegates to orchestration components for implementation details.
      #
      # Enhanced with correlation ID propagation and structured logging.
      #
      # @param task [Tasker::Task] The task to execute
      # @param task_handler [Object] The task handler instance for delegation
      # @return [void]
      def execute_workflow(task, task_handler)
        # Establish correlation ID for the entire workflow execution
        workflow_correlation_id = correlation_id

        with_correlation_id(workflow_correlation_id) do
          log_orchestration_event('workflow_execution', :started,
                                  task_id: task.task_id,
                                  task_name: task.name,
                                  correlation_id: workflow_correlation_id)

          # Publish workflow started event
          publish_workflow_task_started(task.task_id, correlation_id: workflow_correlation_id)

          # Execute the main workflow loop with performance monitoring
          execute_workflow_with_monitoring(task, task_handler)
        end
      rescue StandardError => e
        log_exception(e, context: {
                        task_id: task.task_id,
                        operation: 'workflow_execution',
                        correlation_id: workflow_correlation_id
                      })
        raise
      end

      private

      # Execute workflow with performance monitoring
      #
      # @param task [Tasker::Task] The task to execute
      # @param task_handler [Object] The task handler instance
      # @return [void]
      def execute_workflow_with_monitoring(task, task_handler)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        all_processed_steps = []
        loop_iteration = 0

        log_performance_event('workflow_execution', 0,
                              task_id: task.task_id,
                              operation: 'workflow_start')

        # PROVEN APPROACH: Process steps iteratively until completion or error
        loop do
          break if execute_workflow_iteration(task, task_handler, all_processed_steps, loop_iteration)

          loop_iteration += 1
        end

        # Calculate total execution time
        total_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

        log_performance_event('workflow_execution', total_duration,
                              task_id: task.task_id,
                              total_iterations: loop_iteration,
                              total_steps_processed: all_processed_steps.size,
                              operation: 'workflow_complete')

        # DELEGATE: Finalize via TaskFinalizer (fires events internally)
        finalize_task_with_logging(task, task_handler.get_sequence(task), all_processed_steps, task_handler)
      end

      # Execute a single workflow iteration
      #
      # @param task [Tasker::Task] The task being processed
      # @param task_handler [Object] The task handler instance
      # @param all_processed_steps [Array] Accumulator for processed steps
      # @param iteration [Integer] Current iteration number
      # @return [Boolean] True if workflow should exit, false to continue
      def execute_workflow_iteration(task, task_handler, all_processed_steps, iteration)
        task.reload
        sequence = task_handler.get_sequence(task)

        log_orchestration_event('workflow_iteration', :started,
                                task_id: task.task_id,
                                iteration: iteration,
                                current_status: task.status)

        # Find viable steps with performance monitoring
        viable_steps = find_viable_steps_with_monitoring(task, sequence, task_handler)

        if viable_steps.empty?
          log_orchestration_event('workflow_iteration', :completed,
                                  task_id: task.task_id,
                                  iteration: iteration,
                                  result: 'no_viable_steps',
                                  total_processed: all_processed_steps.size)
          return true # Exit loop
        end

        # Execute viable steps with monitoring
        processed_steps = handle_viable_steps_with_monitoring(task, sequence, viable_steps, task_handler)
        all_processed_steps.concat(processed_steps)

        # Check if blocked by errors
        if blocked_by_errors_with_monitoring?(task, sequence, processed_steps, task_handler)
          log_orchestration_event('workflow_iteration', :completed,
                                  task_id: task.task_id,
                                  iteration: iteration,
                                  result: 'blocked_by_errors',
                                  total_processed: all_processed_steps.size)
          return true # Exit loop
        end

        log_orchestration_event('workflow_iteration', :completed,
                                task_id: task.task_id,
                                iteration: iteration,
                                result: 'continue',
                                steps_processed: processed_steps.size,
                                total_processed: all_processed_steps.size)

        false # Continue loop
      end

      # Get default reenqueuer strategy for production use
      #
      # @return [Tasker::Orchestration::TaskReenqueuer] Production reenqueuer
      def default_reenqueuer_strategy
        Tasker::Orchestration::TaskReenqueuer.new
      end

      # Find steps that are ready for execution with performance monitoring
      #
      # @param task [Tasker::Task] The task being processed
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @param task_handler [Object] The task handler for delegation
      # @return [Array<Tasker::WorkflowStep>] Steps ready for execution
      def find_viable_steps_with_monitoring(task, sequence, _task_handler)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # Delegate to the existing orchestration component
        viable_steps = Orchestration::ViableStepDiscovery.new.find_viable_steps(task, sequence)

        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

        log_performance_event('viable_step_discovery', duration,
                              task_id: task.task_id,
                              step_count: viable_steps.size,
                              sequence_length: sequence.steps.size)

        if viable_steps.any?
          publish_viable_steps_discovered(task.task_id, viable_steps.map(&:workflow_step_id))
        else
          publish_no_viable_steps(task.task_id, reason: 'No steps ready for execution')
        end

        viable_steps
      end

      # Handle execution of viable steps with monitoring
      #
      # @param task [Tasker::Task] The task being processed
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @param viable_steps [Array<Tasker::WorkflowStep>] Steps ready for execution
      # @param task_handler [Object] The task handler for delegation
      # @return [Array<Tasker::WorkflowStep>] Processed steps
      def handle_viable_steps_with_monitoring(task, sequence, viable_steps, task_handler)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        log_orchestration_event('step_batch_execution', :started,
                                task_id: task.task_id,
                                step_count: viable_steps.size,
                                step_names: viable_steps.map(&:name))

        # Delegate to task handler's step executor
        processed_steps = task_handler.send(:step_executor).execute_steps(task, sequence, viable_steps, task_handler)

        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        successful_count = processed_steps.count { |s| s&.status == Tasker::Constants::WorkflowStepStatuses::COMPLETE }

        log_performance_event('step_batch_execution', duration,
                              task_id: task.task_id,
                              step_count: viable_steps.size,
                              processed_count: processed_steps.size,
                              successful_count: successful_count,
                              failure_count: processed_steps.size - successful_count)

        log_orchestration_event('step_batch_execution', :completed,
                                task_id: task.task_id,
                                processed_count: processed_steps.size,
                                successful_count: successful_count,
                                duration_ms: (duration * 1000).round(2))

        processed_steps
      end

      # Check if task is blocked by errors with monitoring
      #
      # @param task [Tasker::Task] The task to check
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @param processed_steps [Array<Tasker::WorkflowStep>] Recently processed steps
      # @param task_handler [Object] The task handler for delegation
      # @return [Boolean] True if blocked by errors
      def blocked_by_errors_with_monitoring?(task, sequence, processed_steps, task_handler)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # Delegate to task handler's task finalizer
        is_blocked = task_handler.send(:task_finalizer).blocked_by_errors?(task, sequence, processed_steps)

        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

        log_performance_event('error_blocking_check', duration,
                              task_id: task.task_id,
                              is_blocked: is_blocked,
                              processed_steps_count: processed_steps.size)

        if is_blocked
          log_orchestration_event('workflow_blocking', :detected,
                                  task_id: task.task_id,
                                  reason: 'blocked_by_errors',
                                  failed_steps: processed_steps.select do |s|
                                    s&.status == Tasker::Constants::WorkflowStepStatuses::ERROR
                                  end.map(&:name))
        end

        is_blocked
      end

      # Finalize the task with structured logging
      #
      # @param task [Tasker::Task] The task to finalize
      # @param sequence [Tasker::Types::StepSequence] The final step sequence
      # @param processed_steps [Array<Tasker::WorkflowStep>] All processed steps
      # @param task_handler [Object] The task handler for delegation
      def finalize_task_with_logging(task, sequence, processed_steps, task_handler)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        log_orchestration_event('task_finalization', :started,
                                task_id: task.task_id,
                                processed_steps_count: processed_steps.size)

        # Publish finalization started event
        publish_task_finalization_started(task, processed_steps_count: processed_steps.size)

        # Call update_annotations hook before finalizing
        if task_handler.respond_to?(:update_annotations)
          task_handler.update_annotations(task, sequence, processed_steps)
        end

        # Delegate to task handler's task finalizer
        task_handler.send(:task_finalizer).finalize_task_with_steps(task, sequence, processed_steps)

        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        task.reload # Get final status

        log_performance_event('task_finalization', duration,
                              task_id: task.task_id,
                              final_status: task.status,
                              processed_steps_count: processed_steps.size)

        # Publish finalization completed event
        publish_task_finalization_completed(task, processed_steps_count: processed_steps.size)

        log_orchestration_event('task_finalization', :completed,
                                task_id: task.task_id,
                                final_status: task.status,
                                duration_ms: (duration * 1000).round(2))
      end
    end
  end
end
