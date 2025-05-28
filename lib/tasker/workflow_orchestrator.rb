# frozen_string_literal: true

require 'dry/events'

module Tasker
  # WorkflowOrchestrator coordinates workflow execution through event-driven orchestration
  #
  # This class subscribes to task and step state transition events and publishes
  # workflow orchestration events to drive the execution of tasks without imperative loops.
  class WorkflowOrchestrator
    include Dry::Events::Publisher[:workflow_orchestrator]

    # Register workflow orchestration events
    register_event('workflow.task_started')
    register_event('workflow.task_completed')
    register_event('workflow.task_failed')
    register_event('workflow.step_completed')
    register_event('workflow.step_failed')
    register_event('workflow.orchestration_requested')

    class << self
      # Subscribe to state transition events from state machines
      #
      # @param bus [Tasker::Events::Bus] The event bus to subscribe to
      def subscribe_to_state_events(bus = nil)
        event_bus = bus || Tasker::LifecycleEvents.bus
        orchestrator = new

        # Subscribe to task state events
        event_bus.subscribe('task.start_requested') do |event|
          orchestrator.handle_task_started(event)
        end

        event_bus.subscribe('task.completed') do |event|
          orchestrator.handle_task_completed(event)
        end

        event_bus.subscribe('task.failed') do |event|
          orchestrator.handle_task_failed(event)
        end

        # Subscribe to step state events
        event_bus.subscribe('step.completed') do |event|
          orchestrator.handle_step_completed(event)
        end

        event_bus.subscribe('step.failed') do |event|
          orchestrator.handle_step_failed(event)
        end

        Rails.logger.info('WorkflowOrchestrator subscribed to state transition events')
      end
    end

    # Handle task start events by publishing workflow orchestration events
    #
    # @param event [Hash] Task start event data
    def handle_task_started(event)
      Rails.logger.debug { "WorkflowOrchestrator: Task started - #{event[:task_id]}" }

      # Publish workflow orchestration event to trigger step discovery
      publish('workflow.task_started', {
                task_id: event[:task_id],
                task_name: event[:task_name],
                orchestrated_at: Time.current
              })
    end

    # Handle task completion events
    #
    # @param event [Hash] Task completion event data
    def handle_task_completed(event)
      Rails.logger.debug { "WorkflowOrchestrator: Task completed - #{event[:task_id]}" }

      publish('workflow.task_completed', {
                task_id: event[:task_id],
                task_name: event[:task_name],
                orchestrated_at: Time.current
              })
    end

    # Handle task failure events
    #
    # @param event [Hash] Task failure event data
    def handle_task_failed(event)
      Rails.logger.debug { "WorkflowOrchestrator: Task failed - #{event[:task_id]}" }

      publish('workflow.task_failed', {
                task_id: event[:task_id],
                task_name: event[:task_name],
                orchestrated_at: Time.current
              })
    end

    # Handle step completion events by triggering workflow progression
    #
    # @param event [Hash] Step completion event data
    def handle_step_completed(event)
      Rails.logger.debug { "WorkflowOrchestrator: Step completed - #{event[:step_id]} for task #{event[:task_id]}" }

      # When a step completes, we need to discover if new steps become viable
      publish('workflow.step_completed', {
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
      Rails.logger.debug { "WorkflowOrchestrator: Step failed - #{event[:step_id]} for task #{event[:task_id]}" }

      publish('workflow.step_failed', {
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
      Rails.logger.debug { "WorkflowOrchestrator: Requesting orchestration for task #{task_id}" }

      publish('workflow.orchestration_requested', {
                task_id: task_id,
                orchestrated_at: Time.current
              })
    end
  end
end
