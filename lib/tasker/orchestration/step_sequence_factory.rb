# frozen_string_literal: true

module Tasker
  module Orchestration
    # StepSequenceFactory handles creation and management of step sequences
    #
    # This component is responsible for:
    # - Getting workflow steps for tasks
    # - Establishing step dependencies and defaults
    # - Creating StepSequence objects
    class StepSequenceFactory
      class << self
        # Get the step sequence for a task
        #
        # Retrieves all workflow steps for the task and establishes their dependencies.
        #
        # @param task [Tasker::Task] The task to get the sequence for
        # @param task_handler [Object] The task handler instance
        # @return [Tasker::Types::StepSequence] The sequence of workflow steps
        def get_sequence(task, task_handler)
          new.get_sequence(task, task_handler)
        end

        # Create sequence for a task (used during task initialization)
        #
        # @param task [Tasker::Task] The task to create sequence for
        # @param task_handler [Object] The task handler instance
        # @return [Tasker::Types::StepSequence] The created sequence
        def create_sequence_for_task!(task, task_handler)
          new.create_sequence_for_task!(task, task_handler)
        end
      end

      # Get the step sequence for a task
      #
      # @param task [Tasker::Task] The task to get the sequence for
      # @param task_handler [Object] The task handler instance
      # @return [Tasker::Types::StepSequence] The sequence of workflow steps
      def get_sequence(task, task_handler)
        steps = Tasker::WorkflowStep.get_steps_for_task(task, task_handler.step_templates)
        establish_step_dependencies_and_defaults(task, steps, task_handler)
        Tasker::Types::StepSequence.new(steps: steps)
      end

      # Create sequence for a task (used during task initialization)
      #
      # @param task [Tasker::Task] The task to create sequence for
      # @param task_handler [Object] The task handler instance
      # @return [Tasker::Types::StepSequence] The created sequence
      def create_sequence_for_task!(task, task_handler)
        steps = Tasker::WorkflowStep.get_steps_for_task(task, task_handler.step_templates)
        establish_step_dependencies_and_defaults(task, steps, task_handler)
        Tasker::Types::StepSequence.new(steps: steps)
      end

      private

      # Establish step dependencies and defaults using task handler hook
      #
      # @param task [Tasker::Task] The task being processed
      # @param steps [Array<Tasker::WorkflowStep>] The steps to establish dependencies for
      # @param task_handler [Object] The task handler instance
      def establish_step_dependencies_and_defaults(task, steps, task_handler)
        # Call the task handler's hook method if it exists
        if task_handler.respond_to?(:establish_step_dependencies_and_defaults)
          task_handler.establish_step_dependencies_and_defaults(task, steps)
        end
      end
    end
  end
end
