# frozen_string_literal: true

require_relative '../events/event_payload_builder'

module Tasker
  module Concerns
    # EventPublisher provides a clean interface for publishing events
    #
    # This concern provides domain-specific event publishing methods that automatically
    # build standardized payloads and resolve event constants. The API is designed for
    # maximum clarity and minimum cognitive overhead.
    #
    # Usage:
    #   include Tasker::Concerns::EventPublisher
    #
    #   # Step events - method name determines event type automatically
    #   publish_step_completed(step, operation_count: 42)
    #   publish_step_failed(step, error: exception)
    #   publish_step_started(step)
    #
    #   # Task events - clean and obvious
    #   publish_task_started(task)
    #   publish_task_completed(task, total_duration: 120.5)
    #   publish_task_failed(task, error_message: "Payment failed")
    module EventPublisher
      extend ActiveSupport::Concern

      # ========================================================================
      # CLEAN STEP EVENT PUBLISHING - METHOD NAME = EVENT TYPE
      # ========================================================================

      # Publish step started event
      # Automatically resolves to StepEvents::EXECUTION_REQUESTED with :started event type
      #
      # @param step [WorkflowStep] The step being started
      # @param context [Hash] Additional context to merge into payload
      # @return [void]
      def publish_step_started(step, **context)
        payload = build_step_payload(step, :started, context)
        publish_event(Tasker::Constants::StepEvents::EXECUTION_REQUESTED, payload)
      end

      # Publish step before handle event
      # Automatically resolves to StepEvents::BEFORE_HANDLE with :before_handle event type
      #
      # @param step [WorkflowStep] The step about to be handled
      # @param context [Hash] Additional context to merge into payload
      # @return [void]
      def publish_step_before_handle(step, **context)
        payload = build_step_payload(step, :before_handle, context)
        publish_event(Tasker::Constants::StepEvents::BEFORE_HANDLE, payload)
      end

      # Publish step completed event
      # Automatically resolves to StepEvents::COMPLETED with :completed event type
      #
      # @param step [WorkflowStep] The step that completed
      # @param context [Hash] Additional context to merge into payload
      # @return [void]
      def publish_step_completed(step, **context)
        payload = build_step_payload(step, :completed, context)
        publish_event(Tasker::Constants::StepEvents::COMPLETED, payload)
      end

      # Publish step failed event
      # Automatically resolves to StepEvents::FAILED with :failed event type
      # Automatically extracts error information if :error is provided
      #
      # @param step [WorkflowStep] The step that failed
      # @param error [Exception, nil] The exception that caused the failure
      # @param context [Hash] Additional context to merge into payload
      # @return [void]
      def publish_step_failed(step, error: nil, **context)
        # Automatically extract error information into context
        if error
          context = context.merge(
            error_message: error.message,
            error_class: error.class.name,
            backtrace: error.backtrace&.first(10)
          )
        end

        payload = build_step_payload(step, :failed, context)
        publish_event(Tasker::Constants::StepEvents::FAILED, payload)
      end

      # Publish step retry requested event
      # Automatically resolves to StepEvents::RETRY_REQUESTED with :retry event type
      #
      # @param step [WorkflowStep] The step being retried
      # @param retry_reason [String] The reason for the retry
      # @param context [Hash] Additional context to merge into payload
      # @return [void]
      def publish_step_retry_requested(step, retry_reason: 'Step execution failed', **context)
        context = context.merge(retry_reason: retry_reason)
        payload = build_step_payload(step, :retry, context)
        publish_event(Tasker::Constants::StepEvents::RETRY_REQUESTED, payload)
      end

      # Publish step cancelled event
      # Automatically resolves to StepEvents::CANCELLED with :cancelled event type
      #
      # @param step [WorkflowStep] The step being cancelled
      # @param cancellation_reason [String] The reason for cancellation
      # @param context [Hash] Additional context to merge into payload
      # @return [void]
      def publish_step_cancelled(step, cancellation_reason: 'Step cancelled', **context)
        context = context.merge(cancellation_reason: cancellation_reason)
        payload = build_step_payload(step, :cancelled, context)
        publish_event(Tasker::Constants::StepEvents::CANCELLED, payload)
      end

      # ========================================================================
      # CLEAN TASK EVENT PUBLISHING - METHOD NAME = EVENT TYPE
      # ========================================================================

      # Publish task started event
      # Automatically resolves to TaskEvents::START_REQUESTED with :started event type
      #
      # @param task [Task] The task being started
      # @param context [Hash] Additional context to merge into payload
      # @return [void]
      def publish_task_started(task, **context)
        payload = build_task_payload(task, :started, context)
        publish_event(Tasker::Constants::TaskEvents::START_REQUESTED, payload)
      end

      # Publish task completed event
      # Automatically resolves to TaskEvents::COMPLETED with :completed event type
      #
      # @param task [Task] The task that completed
      # @param context [Hash] Additional context to merge into payload
      # @return [void]
      def publish_task_completed(task, **context)
        payload = build_task_payload(task, :completed, context)
        publish_event(Tasker::Constants::TaskEvents::COMPLETED, payload)
      end

      # Publish task failed event
      # Automatically resolves to TaskEvents::FAILED with :failed event type
      #
      # @param task [Task] The task that failed
      # @param error_message [String] The error message
      # @param error_steps [Array] Array of failed step information
      # @param context [Hash] Additional context to merge into payload
      # @return [void]
      def publish_task_failed(task, error_message: 'Task execution failed', error_steps: [], **context)
        context = context.merge(
          error_message: error_message,
          error_steps: error_steps
        )

        payload = build_task_payload(task, :failed, context)
        publish_event(Tasker::Constants::TaskEvents::FAILED, payload)
      end

      # Publish task retry requested event
      # Automatically resolves to TaskEvents::RETRY_REQUESTED with :retry event type
      #
      # @param task [Task] The task being retried
      # @param retry_reason [String] The reason for the retry
      # @param context [Hash] Additional context to merge into payload
      # @return [void]
      def publish_task_retry_requested(task, retry_reason: 'Task retry requested', **context)
        context = context.merge(retry_reason: retry_reason)
        payload = build_task_payload(task, :retry, context)
        publish_event(Tasker::Constants::TaskEvents::RETRY_REQUESTED, payload)
      end

      # ========================================================================
      # CLEAN WORKFLOW ORCHESTRATION EVENTS - SIMPLIFIED API
      # ========================================================================

      # Publish workflow task started event (orchestration layer)
      # Automatically resolves to WorkflowEvents::TASK_STARTED
      #
      # @param task_id [String] The task ID
      # @param context [Hash] Additional orchestration context
      # @return [void]
      def publish_workflow_task_started(task_id, **context)
        context = context.merge(task_id: task_id)
        payload = build_orchestration_payload(:task_started, context)
        publish_event(Tasker::Constants::WorkflowEvents::TASK_STARTED, payload)
      end

      # Publish workflow step completed event (orchestration layer)
      # Automatically resolves to WorkflowEvents::STEP_COMPLETED
      #
      # @param task_id [String] The task ID
      # @param step_id [String] The step ID
      # @param context [Hash] Additional orchestration context
      # @return [void]
      def publish_workflow_step_completed(task_id, step_id, **context)
        context = context.merge(task_id: task_id, step_id: step_id)
        payload = build_orchestration_payload(:step_completed, context)
        publish_event(Tasker::Constants::WorkflowEvents::STEP_COMPLETED, payload)
      end

      # Publish viable steps discovered event
      # Automatically resolves to WorkflowEvents::VIABLE_STEPS_DISCOVERED
      #
      # @param task_id [String] The task ID
      # @param step_ids [Array<String>] Array of step IDs ready for execution
      # @param processing_mode [String] The processing mode
      # @param context [Hash] Additional orchestration context
      # @return [void]
      def publish_viable_steps_discovered(task_id, step_ids, processing_mode: 'concurrent', **context)
        context = context.merge(
          task_id: task_id,
          step_ids: step_ids,
          processing_mode: processing_mode,
          step_count: step_ids.size
        )

        payload = build_orchestration_payload(:viable_steps_discovered, context)
        publish_event(Tasker::Constants::WorkflowEvents::VIABLE_STEPS_DISCOVERED, payload)
      end

      # Publish no viable steps event
      # Automatically resolves to WorkflowEvents::NO_VIABLE_STEPS
      #
      # @param task_id [String] The task ID
      # @param reason [String] The reason no viable steps were found
      # @param context [Hash] Additional orchestration context
      # @return [void]
      def publish_no_viable_steps(task_id, reason: 'No steps ready for execution', **context)
        context = context.merge(task_id: task_id, reason: reason)
        payload = build_orchestration_payload(:no_viable_steps, context)
        publish_event(Tasker::Constants::WorkflowEvents::NO_VIABLE_STEPS, payload)
      end

      # ========================================================================
      # CONTEXT-AWARE EVENT PUBLISHING (Advanced - for special cases)
      # ========================================================================

      # Automatically determine and publish the appropriate step event based on step state
      # This method uses the step's current state to infer the most appropriate event type
      #
      # @param step [WorkflowStep] The step object
      # @param context_hint [Symbol, nil] Optional hint about the context
      # @param context [Hash] Additional context to merge into payload
      # @return [void]
      def publish_step_event_for_context(step, context_hint: nil, **context)
        event_type = context_hint || infer_step_event_type_from_state(step)

        case event_type
        when :started, :execution_requested
          publish_step_started(step, **context)
        when :completed, :success
          publish_step_completed(step, **context)
        when :failed, :failure, :error
          publish_step_failed(step, **context)
        when :retry, :retry_requested
          publish_step_retry_requested(step, **context)
        when :cancelled
          publish_step_cancelled(step, **context)
        else
          Rails.logger.warn("Unknown step event context: #{event_type} for step #{step.workflow_step_id}")
        end
      end

      # Infer step event type from step state and context
      #
      # @param step [WorkflowStep] The step object
      # @return [Symbol] The inferred event type
      def infer_step_event_type_from_state(step)
        case step.status
        when Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS
          :started
        when Tasker::Constants::WorkflowStepStatuses::COMPLETE
          :completed
        when Tasker::Constants::WorkflowStepStatuses::ERROR
          :failed
        when Tasker::Constants::WorkflowStepStatuses::CANCELLED
          :cancelled
        else
          :started # Default fallback
        end
      end

      private

      # Core publish method - used internally by domain-specific methods
      #
      # @param event_constant [String] The event constant
      # @param payload [Hash] The event payload
      # @return [void]
      def publish_event(event_constant, payload = {})
        # Add timestamp if not present
        payload[:timestamp] ||= Time.current

        # Publish through the unified publisher
        Tasker::Events::Publisher.instance.publish(event_constant, payload)
      rescue StandardError => e
        # Trap publishing errors so they don't break core system flow
        Rails.logger.error { "Error publishing event #{event_constant}: #{e.message}" }
      end

      # Build standardized step payload automatically
      # Method name determines event type, no redundant parameters needed
      #
      # @param step [WorkflowStep] The step object
      # @param event_type [Symbol] The event type (inferred from calling method)
      # @param context [Hash] Additional context to merge
      # @return [Hash] Standardized event payload
      def build_step_payload(step, event_type, context = {})
        Tasker::Events::EventPayloadBuilder.build_step_payload(
          step,
          step.task,
          event_type: event_type,
          additional_context: context
        )
      end

      # Build standardized task payload automatically
      # Method name determines event type, no redundant parameters needed
      #
      # @param task [Task] The task object
      # @param event_type [Symbol] The event type (inferred from calling method)
      # @param context [Hash] Additional context to merge
      # @return [Hash] Standardized event payload
      def build_task_payload(task, event_type, context = {})
        Tasker::Events::EventPayloadBuilder.build_task_payload(
          task,
          event_type: event_type,
          additional_context: context
        )
      end

      # Build standardized orchestration payload automatically
      # Method name determines event type, no redundant parameters needed
      #
      # @param event_type [Symbol] The orchestration event type
      # @param context [Hash] The orchestration context
      # @return [Hash] Standardized orchestration payload
      def build_orchestration_payload(event_type, context = {})
        Tasker::Events::EventPayloadBuilder.build_orchestration_payload(
          event_type: event_type,
          context: context
        )
      end
    end
  end
end
