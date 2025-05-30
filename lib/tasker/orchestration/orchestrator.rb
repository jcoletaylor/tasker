# frozen_string_literal: true

require 'dry/events'

module Tasker
  module Orchestration
    # Orchestrator coordinates workflow execution through event-driven orchestration
    #
    # This class subscribes to task and step state transition events and publishes
    # workflow orchestration events to drive the execution of tasks without imperative loops.
    class Orchestrator
      include Dry::Events::Publisher[:workflow_orchestrator]

      # Register workflow orchestration events
      register_event(Tasker::Constants::WorkflowEvents::TASK_STARTED)
      register_event(Tasker::Constants::WorkflowEvents::TASK_COMPLETED)
      register_event(Tasker::Constants::WorkflowEvents::TASK_FAILED)
      register_event(Tasker::Constants::WorkflowEvents::STEP_COMPLETED)
      register_event(Tasker::Constants::WorkflowEvents::STEP_FAILED)
      register_event(Tasker::Constants::WorkflowEvents::ORCHESTRATION_REQUESTED)

      class << self
        # Subscribe to state transition events from state machines
        #
        # @param bus [Tasker::Events::Bus] The event bus to subscribe to
        def subscribe_to_state_events(bus = nil)
          event_bus = bus || Tasker::LifecycleEvents.bus
          orchestrator = new

          # Subscribe to task state events
          event_bus.subscribe(Tasker::Constants::LifecycleEvents::TASK_START_REQUESTED) do |event|
            orchestrator.handle_task_started(event)
          end

          event_bus.subscribe(Tasker::Constants::TaskEvents::COMPLETED) do |event|
            orchestrator.handle_task_completed(event)
          end

          event_bus.subscribe(Tasker::Constants::TaskEvents::FAILED) do |event|
            orchestrator.handle_task_failed(event)
          end

          # Subscribe to step state events
          event_bus.subscribe(Tasker::Constants::StepEvents::COMPLETED) do |event|
            orchestrator.handle_step_completed(event)
          end

          event_bus.subscribe(Tasker::Constants::StepEvents::FAILED) do |event|
            orchestrator.handle_step_failed(event)
          end

          Rails.logger.info('Tasker::Orchestration::Orchestrator subscribed to state transition events')
        end
      end

      # Handle task start events by publishing workflow orchestration events
      #
      # @param event [Hash] Task start event data
      def handle_task_started(event)
        Rails.logger.debug { "Orchestrator: Task started - #{event[:task_id]}" }

        # Publish workflow orchestration event to trigger step discovery
        publish(Tasker::Constants::WorkflowEvents::TASK_STARTED, {
                  task_id: event[:task_id],
                  task_name: event[:task_name],
                  orchestrated_at: Time.current
                })
      end

      # Handle task completion events
      #
      # @param event [Hash] Task completion event data
      def handle_task_completed(event)
        Rails.logger.debug { "Orchestrator: Task completed - #{event[:task_id]}" }

        publish(Tasker::Constants::WorkflowEvents::TASK_COMPLETED, {
                  task_id: event[:task_id],
                  task_name: event[:task_name],
                  orchestrated_at: Time.current
                })
      end

      # Handle task failure events
      #
      # @param event [Hash] Task failure event data
      def handle_task_failed(event)
        Rails.logger.debug { "Orchestrator: Task failed - #{event[:task_id]}" }

        publish(Tasker::Constants::WorkflowEvents::TASK_FAILED, {
                  task_id: event[:task_id],
                  task_name: event[:task_name],
                  orchestrated_at: Time.current
                })
      end

      # Handle step completion events by triggering workflow progression
      #
      # @param event [Hash] Step completion event data
      def handle_step_completed(event)
        Rails.logger.debug { "Orchestrator: Step completed - #{event[:step_id]} for task #{event[:task_id]}" }

        # When a step completes, we need to discover if new steps become viable
        publish(Tasker::Constants::WorkflowEvents::STEP_COMPLETED, {
                  task_id: event[:task_id],
                  step_id: event[:step_id],
                  step_name: event[:step_name],
                  orchestrated_at: Time.current
                })

        # Request orchestration to find next viable steps
        request_orchestration(event[:task_id])
      end

      # Handle step failure events
      #
      # @param event [Hash] Step failure event data
      def handle_step_failed(event)
        Rails.logger.debug { "Orchestrator: Step failed - #{event[:step_id]} for task #{event[:task_id]}" }

        publish(Tasker::Constants::WorkflowEvents::STEP_FAILED, {
                  task_id: event[:task_id],
                  step_id: event[:step_id],
                  step_name: event[:step_name],
                  orchestrated_at: Time.current
                })

        # Request orchestration to handle failure and potentially retry or fail task
        request_orchestration(event[:task_id])
      end

      # Request workflow orchestration for a specific task
      #
      # This is the main entry point for triggering workflow progression
      #
      # @param task_id [Integer] The task ID to orchestrate
      def request_orchestration(task_id)
        Rails.logger.debug { "Orchestrator: Requesting orchestration for task #{task_id}" }

        publish(Tasker::Constants::WorkflowEvents::ORCHESTRATION_REQUESTED, {
                  task_id: task_id,
                  orchestrated_at: Time.current
                })
      end
    end
  end
end
