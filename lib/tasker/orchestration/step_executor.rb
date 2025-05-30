# frozen_string_literal: true

require 'dry/events'
require 'concurrent'

module Tasker
  module Orchestration
    # StepExecutor handles the execution of workflow steps via state machine transitions
    #
    # This class extracts the step execution logic from TaskHandler::InstanceMethods
    # and makes it event-driven, responding to viable step discovery events.
    class StepExecutor
      include Dry::Events::Publisher[:step_executor]

      # Register events that this component publishes
      register_event(Tasker::Constants::WorkflowEvents::STEPS_EXECUTION_STARTED)
      register_event(Tasker::Constants::WorkflowEvents::STEPS_EXECUTION_COMPLETED)
      register_event(Tasker::Constants::WorkflowEvents::STEP_EXECUTION_FAILED)

      class << self
        # Subscribe to workflow events for step execution
        #
        # @param bus [Tasker::Events::Bus] The event bus to subscribe to
        def subscribe_to_workflow_events(bus = nil)
          event_bus = bus || Tasker::LifecycleEvents.bus
          executor = new

          # Subscribe to viable steps discovered events
          event_bus.subscribe(Tasker::Constants::WorkflowEvents::VIABLE_STEPS_DISCOVERED) do |event|
            executor.execute_viable_steps(event)
          end

          Rails.logger.info('Tasker::Orchestration::StepExecutor subscribed to workflow events')
        end
      end

      # Execute viable steps based on the discovered steps event
      #
      # @param event [Hash] The viable steps discovered event data
      def execute_viable_steps(event)
        task_id = event[:task_id]
        step_ids = event[:step_ids]
        processing_mode = event[:processing_mode] || 'sequential'

        Rails.logger.debug do
          "StepExecutor: Executing #{step_ids.size} steps for task #{task_id} in #{processing_mode} mode"
        end

        # Load the steps to execute
        steps = Tasker::WorkflowStep.where(workflow_step_id: step_ids)

        publish(Tasker::Constants::WorkflowEvents::STEPS_EXECUTION_STARTED, {
                  task_id: task_id,
                  step_ids: step_ids,
                  processing_mode: processing_mode,
                  started_at: Time.current
                })

        case processing_mode
        when 'concurrent'
          execute_steps_concurrently(steps)
        when 'sequential'
          execute_steps_sequentially(steps)
        else
          execute_steps_sequentially(steps) # Default to sequential
        end

        publish(Tasker::Constants::WorkflowEvents::STEPS_EXECUTION_COMPLETED, {
                  task_id: task_id,
                  step_ids: step_ids,
                  processing_mode: processing_mode,
                  completed_at: Time.current
                })
      rescue StandardError => e
        Rails.logger.error { "StepExecutor: Error executing steps for task #{task_id}: #{e.message}" }

        publish(Tasker::Constants::WorkflowEvents::STEP_EXECUTION_FAILED, {
                  task_id: task_id,
                  step_ids: step_ids,
                  error: e.message,
                  failed_at: Time.current
                })

        raise
      end

      private

      # Execute steps concurrently using futures
      #
      # @param steps [Array<Tasker::WorkflowStep>] The steps to execute
      def execute_steps_concurrently(steps)
        Rails.logger.debug { "StepExecutor: Executing #{steps.size} steps concurrently" }

        # Create futures for each step
        futures = steps.map do |step|
          Concurrent::Future.execute do
            execute_single_step(step)
          end
        end

        # Wait for all futures to complete with timeout
        futures.each do |future|
          # 30 second timeout per step to prevent indefinite hanging
          future.value(30)
        rescue StandardError => e
          Rails.logger.error("StepExecutor: Error in concurrent step execution: #{e.message}")
          # Continue with other steps even if one fails
        end
      end

      # Execute steps sequentially
      #
      # @param steps [Array<Tasker::WorkflowStep>] The steps to execute
      def execute_steps_sequentially(steps)
        Rails.logger.debug { "StepExecutor: Executing #{steps.size} steps sequentially" }

        steps.each do |step|
          execute_single_step(step)
        end
      end

      # Execute a single step by transitioning it to in_progress
      #
      # This triggers the state machine callbacks that handle the actual execution
      #
      # @param step [Tasker::WorkflowStep] The step to execute
      def execute_single_step(step)
        Rails.logger.debug { "StepExecutor: Executing step #{step.workflow_step_id} (#{step.name})" }

        # Mark the step as in_process to prevent duplicate execution
        step.update_column(:in_process, true)

        # Transition the step to in_progress, which will trigger execution via state machine callbacks
        # The actual execution logic is in the StepStateMachine after_transition callback
        step.state_machine.transition_to!(Constants::WorkflowStepStatuses::IN_PROGRESS)
      rescue StandardError => e
        Rails.logger.error { "StepExecutor: Failed to execute step #{step.workflow_step_id}: #{e.message}" }

        # Reset in_process flag on failure
        step.update_column(:in_process, false)

        # Transition to error state
        step.state_machine.transition_to!(Constants::WorkflowStepStatuses::ERROR)

        raise
      end
    end
  end
end
