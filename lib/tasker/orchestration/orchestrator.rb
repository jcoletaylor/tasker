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
          event_bus.subscribe(Tasker::Constants::TaskEvents::START_REQUESTED) do |event|
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

        # Build the workflow event payload
        workflow_event_payload = {
          task_id: event[:task_id],
          task_name: event[:task_name],
          orchestrated_at: Time.current
        }

        # Publish to Dry::Events bus for internal orchestration
        publish(Tasker::Constants::WorkflowEvents::TASK_STARTED, workflow_event_payload)

        # Also publish to main LifecycleEvents bus for external subscribers (tests, monitoring, etc.)
        Tasker::LifecycleEvents.fire(
          Tasker::Constants::WorkflowEvents::TASK_STARTED,
          workflow_event_payload
        )
      end

      # Handle task completion events
      #
      # @param event [Hash] Task completion event data
      def handle_task_completed(event)
        Rails.logger.debug { "Orchestrator: Task completed - #{event[:task_id]}" }

        # Build the workflow event payload
        workflow_event_payload = {
          task_id: event[:task_id],
          task_name: event[:task_name],
          orchestrated_at: Time.current
        }

        # Publish to both event buses
        publish(Tasker::Constants::WorkflowEvents::TASK_COMPLETED, workflow_event_payload)
        Tasker::LifecycleEvents.fire(
          Tasker::Constants::WorkflowEvents::TASK_COMPLETED,
          workflow_event_payload
        )
      end

      # Handle task failure events
      #
      # @param event [Hash] Task failure event data
      def handle_task_failed(event)
        Rails.logger.debug { "Orchestrator: Task failed - #{event[:task_id]}" }

        # Build the workflow event payload
        workflow_event_payload = {
          task_id: event[:task_id],
          task_name: event[:task_name],
          orchestrated_at: Time.current
        }

        # Publish to both event buses
        publish(Tasker::Constants::WorkflowEvents::TASK_FAILED, workflow_event_payload)
        Tasker::LifecycleEvents.fire(
          Tasker::Constants::WorkflowEvents::TASK_FAILED,
          workflow_event_payload
        )
      end

      # Handle step completion events by triggering workflow progression
      #
      # @param event [Hash] Step completion event data
      def handle_step_completed(event)
        Rails.logger.debug { "Orchestrator: Step completed - #{event[:step_id]} for task #{event[:task_id]}" }

        # Build the workflow event payload
        workflow_event_payload = {
          task_id: event[:task_id],
          step_id: event[:step_id],
          step_name: event[:step_name],
          orchestrated_at: Time.current
        }

        # When a step completes, we need to discover if new steps become viable
        publish(Tasker::Constants::WorkflowEvents::STEP_COMPLETED, workflow_event_payload)
        Tasker::LifecycleEvents.fire(
          Tasker::Constants::WorkflowEvents::STEP_COMPLETED,
          workflow_event_payload
        )

        # Request orchestration to find next viable steps
        request_orchestration(event[:task_id])
      end

      # Handle step failure events
      #
      # @param event [Hash] Step failure event data
      def handle_step_failed(event)
        Rails.logger.debug { "Orchestrator: Step failed - #{event[:step_id]} for task #{event[:task_id]}" }

        # Build the workflow event payload
        workflow_event_payload = {
          task_id: event[:task_id],
          step_id: event[:step_id],
          step_name: event[:step_name],
          orchestrated_at: Time.current
        }

        # Publish to both event buses
        publish(Tasker::Constants::WorkflowEvents::STEP_FAILED, workflow_event_payload)
        Tasker::LifecycleEvents.fire(
          Tasker::Constants::WorkflowEvents::STEP_FAILED,
          workflow_event_payload
        )

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

        # Build the workflow event payload
        workflow_event_payload = {
          task_id: task_id,
          orchestrated_at: Time.current
        }

        # Publish to both event buses
        publish(Tasker::Constants::WorkflowEvents::ORCHESTRATION_REQUESTED, workflow_event_payload)
        Tasker::LifecycleEvents.fire(
          Tasker::Constants::WorkflowEvents::ORCHESTRATION_REQUESTED,
          workflow_event_payload
        )
      end
    end
  end
end
