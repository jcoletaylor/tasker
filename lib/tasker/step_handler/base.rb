# frozen_string_literal: true

require_relative '../concerns/event_publisher'

module Tasker
  module StepHandler
    # Base class for all step handlers that defines the common interface
    # and provides lifecycle event handling
    #
    # Step handlers are responsible for executing the actual logic of
    # workflow steps and reporting results.
    class Base
      include Tasker::Concerns::EventPublisher

      # Creates a new step handler instance
      #
      # @param config [Object, nil] Optional configuration for the handler
      # @return [Base] A new step handler instance
      def initialize(config: nil)
        @config = config
      end

      # Handles the execution of a workflow step
      #
      # Fires lifecycle events before handling the step and then
      # delegates to the subclass's implementation of the process method.
      #
      # @param task [Tasker::Task] The task being executed
      # @param sequence [Tasker::Types::StepSequence] The sequence of steps
      # @param step [Tasker::WorkflowStep] The current step being handled
      # @return [Object] The result of processing the step
      def handle(task, sequence, step)
        # Fire the before_handle event
        publish_event(
          Tasker::LifecycleEvents::Events::Step::BEFORE_HANDLE,
          {
            task_id: task.task_id,
            step_id: step.workflow_step_id,
            step_name: step.name
          }
        )

        # Subclasses should implement the process method
        process(task, sequence, step)
      end

      # The main processing logic for a step
      # Subclasses must implement this method
      #
      # @param task [Tasker::Task] The task being executed
      # @param sequence [Tasker::Types::StepSequence] The sequence of steps
      # @param step [Tasker::WorkflowStep] The current step being handled
      # @raise [NotImplementedError] If not implemented by a subclass
      def process(task, sequence, step)
        raise NotImplementedError, 'Subclasses must implement this method'
      end
    end
  end
end
