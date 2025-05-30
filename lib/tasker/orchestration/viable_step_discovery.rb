# frozen_string_literal: true

require 'dry/events'

module Tasker
  module Orchestration
    # ViableStepDiscovery discovers which steps can be executed based on workflow state
    #
    # This class extracts the viable step discovery logic from TaskHandler::InstanceMethods
    # and makes it event-driven, responding to workflow orchestration events.
    class ViableStepDiscovery
      include Dry::Events::Publisher[:step_discovery]

      # Register events that this component publishes
      register_event(Tasker::Constants::WorkflowEvents::VIABLE_STEPS_DISCOVERED)
      register_event(Tasker::Constants::WorkflowEvents::NO_VIABLE_STEPS)
      register_event(Tasker::Constants::WorkflowEvents::VIABLE_STEPS_BATCH_READY)

      class << self
        # Subscribe to workflow orchestration events
        #
        # @param bus [Tasker::Events::Bus] The event bus to subscribe to
        def subscribe_to_orchestration_events(bus = nil)
          event_bus = bus || Tasker::LifecycleEvents.bus
          discovery = new

          # Subscribe to workflow orchestration requests
          event_bus.subscribe(Tasker::Constants::WorkflowEvents::ORCHESTRATION_REQUESTED) do |event|
            discovery.discover_viable_steps_for_task(event[:task_id])
          end

          # Subscribe to task started events
          event_bus.subscribe(Tasker::Constants::WorkflowEvents::TASK_STARTED) do |event|
            discovery.discover_viable_steps_for_task(event[:task_id])
          end

          # Subscribe to step completion events to trigger new discovery
          event_bus.subscribe(Tasker::Constants::WorkflowEvents::STEP_COMPLETED) do |event|
            discovery.discover_viable_steps_for_task(event[:task_id])
          end

          Rails.logger.info('Tasker::Orchestration::ViableStepDiscovery subscribed to orchestration events')
        end
      end

      # Discover viable steps for a specific task
      #
      # @param task_id [Integer] The task ID to discover steps for
      def discover_viable_steps_for_task(task_id)
        task = Tasker::Task.find(task_id)

        Rails.logger.debug { "ViableStepDiscovery: Discovering viable steps for task #{task_id}" }

        # Get the current sequence - extracted from TaskHandler logic
        sequence = get_sequence(task)

        # Find viable steps using the extracted logic
        viable_steps = find_viable_steps(task, sequence)

        if viable_steps.any?
          step_names = viable_steps.map(&:name)
          step_ids = viable_steps.map(&:workflow_step_id)

          Rails.logger.debug do
            "ViableStepDiscovery: Found #{viable_steps.size} viable steps: #{step_names.join(', ')}"
          end

          # Build the workflow event payload
          workflow_event_payload = {
            task_id: task_id,
            step_ids: step_ids,
            step_names: step_names,
            count: viable_steps.size,
            processing_mode: determine_processing_mode(task),
            discovered_at: Time.current
          }

          # Publish to both event buses
          publish(Tasker::Constants::WorkflowEvents::VIABLE_STEPS_DISCOVERED, workflow_event_payload)
          Tasker::LifecycleEvents.fire(
            Tasker::Constants::WorkflowEvents::VIABLE_STEPS_DISCOVERED,
            workflow_event_payload
          )
        else
          Rails.logger.debug { "ViableStepDiscovery: No viable steps found for task #{task_id}" }

          # Build the workflow event payload for no viable steps
          workflow_event_payload = {
            task_id: task_id,
            task_name: task.name,
            discovered_at: Time.current
          }

          # Publish to both event buses
          publish(Tasker::Constants::WorkflowEvents::NO_VIABLE_STEPS, workflow_event_payload)
          Tasker::LifecycleEvents.fire(
            Tasker::Constants::WorkflowEvents::NO_VIABLE_STEPS,
            workflow_event_payload
          )
        end
      rescue StandardError => e
        Rails.logger.error { "ViableStepDiscovery: Error discovering steps for task #{task_id}: #{e.message}" }
        raise
      end

      private

      # Get the step sequence for a task (extracted from TaskHandler)
      #
      # @param task [Tasker::Task] The task to get the sequence for
      # @return [Tasker::Types::StepSequence] The sequence of workflow steps
      def get_sequence(task)
        # This logic is extracted from TaskHandler::InstanceMethods#get_sequence
        # We'll need to make this more generic or inject the handler

        # For now, we'll use the WorkflowStep model's logic directly
        # In a future iteration, we might inject a TaskHandler or make this configurable
        steps = task.workflow_steps.includes(:named_step, :parents, :children)
        Tasker::Types::StepSequence.new(steps: steps.to_a)
      end

      # Find viable steps that can be executed (extracted from TaskHandler)
      #
      # @param task [Tasker::Task] The task being processed
      # @param sequence [Tasker::Types::StepSequence] The sequence of steps
      # @return [Array<Tasker::WorkflowStep>] The viable steps
      def find_viable_steps(task, sequence)
        # This logic is extracted from TaskHandler::InstanceMethods#find_viable_steps
        unfinished_steps = sequence.steps.reject { |step| step.processed || step.in_process }

        viable_steps = []
        unfinished_steps.each do |step|
          # Reload to get latest status
          fresh_step = Tasker::WorkflowStep.find(step.workflow_step_id)

          # Skip if step is now processed or in process
          next if fresh_step.processed || fresh_step.in_process

          # Check if step is viable with latest DB state
          viable_steps << fresh_step if Tasker::WorkflowStep.is_step_viable?(fresh_step, task)
        end

        viable_steps
      end

      # Determine the processing mode for a task
      #
      # @param task [Tasker::Task] The task to check
      # @return [String] The processing mode ('concurrent', 'sequential', or 'auto')
      def determine_processing_mode(_task)
        # Default to sequential for now
        # In the future, this could be configurable per task or based on task properties
        'sequential'
      end
    end
  end
end
