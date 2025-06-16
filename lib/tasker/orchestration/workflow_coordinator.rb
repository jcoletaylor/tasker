# frozen_string_literal: true

module Tasker
  module Orchestration
    # WorkflowCoordinator handles the main task execution loop
    #
    # This coordinator extracts the proven loop-based execution logic from TaskHandler
    # and provides a strategy pattern for composition with different reenqueuer strategies.
    # This enables proper testing of the complete workflow execution path.
    class WorkflowCoordinator
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
      # @param task [Tasker::Task] The task to execute
      # @param task_handler [Object] The task handler instance for delegation
      # @return [void]
      def execute_workflow(task, task_handler)
        # PROVEN APPROACH: Process steps iteratively until completion or error
        all_processed_steps = []

        loop do
          task.reload
          sequence = task_handler.get_sequence(task)
          viable_steps = find_viable_steps(task, sequence, task_handler)

          break if viable_steps.empty?

          processed_steps = handle_viable_steps(task, sequence, viable_steps, task_handler)
          all_processed_steps.concat(processed_steps)

          break if blocked_by_errors?(task, sequence, processed_steps, task_handler)
        end

        # DELEGATE: Finalize via TaskFinalizer (fires events internally)
        finalize_task(task, task_handler.get_sequence(task), all_processed_steps, task_handler)
      end

      private

      # Get default reenqueuer strategy for production use
      #
      # @return [Tasker::Orchestration::TaskReenqueuer] Production reenqueuer
      def default_reenqueuer_strategy
        Tasker::Orchestration::TaskReenqueuer.new
      end

      # Find steps that are ready for execution
      #
      # @param task [Tasker::Task] The task being processed
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @param task_handler [Object] The task handler for delegation
      # @return [Array<Tasker::WorkflowStep>] Steps ready for execution
      def find_viable_steps(task, sequence, _task_handler)
        # Delegate to the existing orchestration component
        Orchestration::ViableStepDiscovery.new.find_viable_steps(task, sequence)
      end

      # Handle execution of viable steps
      #
      # @param task [Tasker::Task] The task being processed
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @param viable_steps [Array<Tasker::WorkflowStep>] Steps ready for execution
      # @param task_handler [Object] The task handler for delegation
      # @return [Array<Tasker::WorkflowStep>] Processed steps
      def handle_viable_steps(task, sequence, viable_steps, task_handler)
        # Delegate to task handler's step executor
        task_handler.send(:step_executor).execute_steps(task, sequence, viable_steps, task_handler)
      end

      # Check if task is blocked by errors
      #
      # @param task [Tasker::Task] The task to check
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @param processed_steps [Array<Tasker::WorkflowStep>] Recently processed steps
      # @param task_handler [Object] The task handler for delegation
      # @return [Boolean] True if blocked by errors
      def blocked_by_errors?(task, sequence, processed_steps, task_handler)
        # Delegate to task handler's task finalizer
        task_handler.send(:task_finalizer).blocked_by_errors?(task, sequence, processed_steps)
      end

      # Finalize the task
      #
      # @param task [Tasker::Task] The task to finalize
      # @param sequence [Tasker::Types::StepSequence] The final step sequence
      # @param processed_steps [Array<Tasker::WorkflowStep>] All processed steps
      # @param task_handler [Object] The task handler for delegation
      def finalize_task(task, sequence, processed_steps, task_handler)
        # Call update_annotations hook before finalizing
        if task_handler.respond_to?(:update_annotations)
          task_handler.update_annotations(task, sequence, processed_steps)
        end

        # Delegate to task handler's task finalizer
        task_handler.send(:task_finalizer).finalize_task_with_steps(task, sequence, processed_steps)
      end
    end
  end
end
