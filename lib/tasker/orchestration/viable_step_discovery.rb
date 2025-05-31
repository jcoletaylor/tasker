# frozen_string_literal: true

require_relative '../concerns/lifecycle_event_helpers'
require_relative '../concerns/orchestration_publisher'

module Tasker
  module Orchestration
    # ViableStepDiscovery provides implementation for finding steps ready for execution
    #
    # This class is a simple implementation provider that wraps the existing
    # WorkflowStep.get_viable_steps logic while firing lifecycle events
    # for observability. No complex event subscriptions needed.
    class ViableStepDiscovery
      include Tasker::Concerns::LifecycleEventHelpers
      include Tasker::Concerns::OrchestrationPublisher

      # Find viable steps for execution
      #
      # This is just a clean wrapper around the existing WorkflowStep.get_viable_steps
      # method that fires observability events.
      #
      # @param task [Tasker::Task] The task to find steps for
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @return [Array<Tasker::WorkflowStep>] Array of viable steps
      def find_viable_steps(task, sequence)
        # Use the existing proven logic - this is where the real work happens
        viable_steps = Tasker::WorkflowStep.get_viable_steps(task, sequence)

        # Fire appropriate discovery event based on results through orchestrator
        if viable_steps.any?
          publish_event(
            Tasker::Constants::WorkflowEvents::VIABLE_STEPS_DISCOVERED,
            {
              task_id: task.task_id,
              viable_count: viable_steps.size,
              step_ids: viable_steps.map(&:workflow_step_id),
              step_names: viable_steps.map(&:name)
            }
          )
        else
          publish_event(
            Tasker::Constants::WorkflowEvents::NO_VIABLE_STEPS,
            {
              task_id: task.task_id,
              total_steps_checked: sequence.steps.size
            }
          )
        end

        Rails.logger.debug("ViableStepDiscovery: Found #{viable_steps.size} viable steps for task #{task.task_id}")
        viable_steps
      end
    end
  end
end
