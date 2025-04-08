# frozen_string_literal: true

module Tasker
  module StepHandler
    class Base
      def initialize(config: nil)
        @config = config
      end

      def handle(task, sequence, step)
        # Fire the before_handle event
        Tasker::LifecycleEvents.fire(
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
      def process(task, sequence, step)
        raise NotImplementedError, 'Subclasses must implement this method'
      end
    end
  end
end
