# frozen_string_literal: true

require_relative '../events/event_payload_builder'

module Tasker
  module Concerns
    # EventPublisher provides a clean interface for publishing events
    #
    # This concern provides domain-specific event publishing methods that automatically
    # build standardized payloads using EventPayloadBuilder. Each method corresponds
    # to a specific event type with context-appropriate parameters.
    #
    # Usage:
    #   include Tasker::Concerns::EventPublisher
    #
    #   # Step events
    #   publish_step_completed(step, operation_count: 42)
    #   publish_step_failed(step, error: exception)
    #
    #   # Task events
    #   publish_task_started(task)
    #   publish_task_completed(task, total_duration: 120.5)
    module EventPublisher
      extend ActiveSupport::Concern

      private

      # Publish an event through the unified Events::Publisher
      #
      # @param event_name [String] The event name/constant
      # @param payload [Hash] The event payload
      # @return [void]
      def publish_event(event_name, payload = {})
        # Add timestamp if not present
        payload[:timestamp] ||= Time.current

        # Publish through the unified publisher
        # If Events::Publisher isn't defined, let it fail fast - that's a real configuration error
        Tasker::Events::Publisher.instance.publish(event_name, payload)
      rescue StandardError => e
        # Trap publishing errors so they don't break core system flow
        # but let configuration errors (missing publisher) bubble up
        Rails.logger.error { "Error publishing event #{event_name}: #{e.message}" }
      end

      # ========================================================================
      # CLEAN DOMAIN-SPECIFIC EVENT PUBLISHING METHODS
      # ========================================================================

      # Step Lifecycle Events - Clean API with automatic payload building
      # Each method automatically builds the appropriate payload and infers event type

      # Publish step started/execution requested event
      #
      # @param step [WorkflowStep] The step being started
      # @param additional_context [Hash] Additional context to merge into payload
      # @return [void]
      def publish_step_started(step, **additional_context)
        payload = Tasker::Events::EventPayloadBuilder.build_step_payload(
          step,
          step.task,
          event_type: :started,
          additional_context: additional_context
        )
        publish_event(Tasker::Constants::StepEvents::EXECUTION_REQUESTED, payload)
      end

      # Publish step before handle event
      #
      # @param step [WorkflowStep] The step about to be handled
      # @param additional_context [Hash] Additional context to merge into payload
      # @return [void]
      def publish_step_before_handle(step, **additional_context)
        payload = Tasker::Events::EventPayloadBuilder.build_step_payload(
          step,
          step.task,
          event_type: :before_handle,
          additional_context: additional_context
        )
        publish_event(Tasker::Constants::StepEvents::BEFORE_HANDLE, payload)
      end

      # Publish step completed event
      #
      # @param step [WorkflowStep] The step that completed
      # @param additional_context [Hash] Additional context to merge into payload
      # @return [void]
      def publish_step_completed(step, **additional_context)
        payload = Tasker::Events::EventPayloadBuilder.build_step_payload(
          step,
          step.task,
          event_type: :completed,
          additional_context: additional_context
        )
        publish_event(Tasker::Constants::StepEvents::COMPLETED, payload)
      end

      # Publish step failed event
      #
      # @param step [WorkflowStep] The step that failed
      # @param error [Exception, nil] The exception that caused the failure (optional)
      # @param additional_context [Hash] Additional context to merge into payload
      # @return [void]
      def publish_step_failed(step, error: nil, **additional_context)
        # Add error information to context if provided
        if error
          additional_context[:error_message] = error.message
          additional_context[:error_class] = error.class.name
          additional_context[:backtrace] = error.backtrace&.first(10) # Limit backtrace size
        end

        payload = Tasker::Events::EventPayloadBuilder.build_step_payload(
          step,
          step.task,
          event_type: :failed,
          additional_context: additional_context
        )
        publish_event(Tasker::Constants::StepEvents::FAILED, payload)
      end

      # Publish step retry requested event
      #
      # @param step [WorkflowStep] The step being retried
      # @param retry_reason [String] The reason for the retry
      # @param additional_context [Hash] Additional context to merge into payload
      # @return [void]
      def publish_step_retry_requested(step, retry_reason: 'Step execution failed', **additional_context)
        additional_context[:retry_reason] = retry_reason

        payload = Tasker::Events::EventPayloadBuilder.build_step_payload(
          step,
          step.task,
          event_type: :retry,
          additional_context: additional_context
        )
        publish_event(Tasker::Constants::StepEvents::RETRY_REQUESTED, payload)
      end

      # Publish step cancelled event
      #
      # @param step [WorkflowStep] The step being cancelled
      # @param cancellation_reason [String] The reason for cancellation
      # @param additional_context [Hash] Additional context to merge into payload
      # @return [void]
      def publish_step_cancelled(step, cancellation_reason: 'Step cancelled', **additional_context)
        additional_context[:cancellation_reason] = cancellation_reason

        payload = Tasker::Events::EventPayloadBuilder.build_step_payload(
          step,
          step.task,
          event_type: :cancelled,
          additional_context: additional_context
        )
        publish_event(Tasker::Constants::StepEvents::CANCELLED, payload)
      end

      # Task Lifecycle Events - Clean API with automatic payload building

      # Publish task started event
      #
      # @param task [Task] The task being started
      # @param additional_context [Hash] Additional context to merge into payload
      # @return [void]
      def publish_task_started(task, **additional_context)
        payload = Tasker::Events::EventPayloadBuilder.build_task_payload(
          task,
          event_type: :started,
          additional_context: additional_context
        )
        publish_event(Tasker::Constants::TaskEvents::START_REQUESTED, payload)
      end

      # Publish task completed event
      #
      # @param task [Task] The task that completed
      # @param additional_context [Hash] Additional context to merge into payload
      # @return [void]
      def publish_task_completed(task, **additional_context)
        payload = Tasker::Events::EventPayloadBuilder.build_task_payload(
          task,
          event_type: :completed,
          additional_context: additional_context
        )
        publish_event(Tasker::Constants::TaskEvents::COMPLETED, payload)
      end

      # Publish task failed event
      #
      # @param task [Task] The task that failed
      # @param error_message [String] The error message
      # @param error_steps [Array] Array of failed step information
      # @param additional_context [Hash] Additional context to merge into payload
      # @return [void]
      def publish_task_failed(task, error_message: 'Task execution failed', error_steps: [], **additional_context)
        additional_context[:error_message] = error_message
        additional_context[:error_steps] = error_steps if error_steps.any?

        payload = Tasker::Events::EventPayloadBuilder.build_task_payload(
          task,
          event_type: :failed,
          additional_context: additional_context
        )
        publish_event(Tasker::Constants::TaskEvents::FAILED, payload)
      end

      # Publish task retry requested event
      #
      # @param task [Task] The task being retried
      # @param retry_reason [String] The reason for the retry
      # @param additional_context [Hash] Additional context to merge into payload
      # @return [void]
      def publish_task_retry_requested(task, retry_reason: 'Task retry requested', **additional_context)
        additional_context[:retry_reason] = retry_reason

        payload = Tasker::Events::EventPayloadBuilder.build_task_payload(
          task,
          event_type: :retry,
          additional_context: additional_context
        )
        publish_event(Tasker::Constants::TaskEvents::RETRY_REQUESTED, payload)
      end

      # Workflow Orchestration Events - Clean API for workflow coordination

      # Publish workflow task started event (orchestration layer)
      #
      # @param task_id [String] The task ID
      # @param additional_context [Hash] Additional orchestration context
      # @return [void]
      def publish_workflow_task_started(task_id, **additional_context)
        context = { task_id: task_id }.merge(additional_context)
        payload = Tasker::Events::EventPayloadBuilder.build_orchestration_payload(
          event_type: :task_started,
          context: context
        )
        publish_event(Tasker::Constants::WorkflowEvents::TASK_STARTED, payload)
      end

      # Publish workflow step completed event (orchestration layer)
      #
      # @param task_id [String] The task ID
      # @param step_id [String] The step ID
      # @param additional_context [Hash] Additional orchestration context
      # @return [void]
      def publish_workflow_step_completed(task_id, step_id, **additional_context)
        context = { task_id: task_id, step_id: step_id }.merge(additional_context)
        payload = Tasker::Events::EventPayloadBuilder.build_orchestration_payload(
          event_type: :step_completed,
          context: context
        )
        publish_event(Tasker::Constants::WorkflowEvents::STEP_COMPLETED, payload)
      end

      # Publish viable steps discovered event
      #
      # @param task_id [String] The task ID
      # @param step_ids [Array<String>] Array of step IDs ready for execution
      # @param processing_mode [String] The processing mode ('concurrent' or 'sequential')
      # @param additional_context [Hash] Additional orchestration context
      # @return [void]
      def publish_viable_steps_discovered(task_id, step_ids, processing_mode: 'concurrent', **additional_context)
        context = {
          task_id: task_id,
          step_ids: step_ids,
          processing_mode: processing_mode,
          step_count: step_ids.size
        }.merge(additional_context)

        payload = Tasker::Events::EventPayloadBuilder.build_orchestration_payload(
          event_type: :viable_steps_discovered,
          context: context
        )
        publish_event(Tasker::Constants::WorkflowEvents::VIABLE_STEPS_DISCOVERED, payload)
      end

      # Publish no viable steps event
      #
      # @param task_id [String] The task ID
      # @param reason [String] The reason no viable steps were found
      # @param additional_context [Hash] Additional orchestration context
      # @return [void]
      def publish_no_viable_steps(task_id, reason: 'No steps ready for execution', **additional_context)
        context = { task_id: task_id, reason: reason }.merge(additional_context)
        payload = Tasker::Events::EventPayloadBuilder.build_orchestration_payload(
          event_type: :no_viable_steps,
          context: context
        )
        publish_event(Tasker::Constants::WorkflowEvents::NO_VIABLE_STEPS, payload)
      end

      # ========================================================================
      # CONTEXT-AWARE EVENT PUBLISHING (Advanced feature)
      # ========================================================================

      # Automatically determine and publish the appropriate step event based on step state
      # This method uses the step's current state to infer the most appropriate event type
      #
      # @param step [WorkflowStep] The step object
      # @param context_hint [Symbol, nil] Optional hint about the context (:success, :failure, :retry)
      # @param additional_context [Hash] Additional context to merge into payload
      # @return [void]
      def publish_step_event_for_context(step, context_hint: nil, **additional_context)
        # Infer event type from context or step state
        event_type = context_hint || infer_step_event_type_from_state(step)

        case event_type
        when :started, :execution_requested
          publish_step_started(step, **additional_context)
        when :completed, :success
          publish_step_completed(step, **additional_context)
        when :failed, :failure, :error
          publish_step_failed(step, **additional_context)
        when :retry, :retry_requested
          publish_step_retry_requested(step, **additional_context)
        when :cancelled
          publish_step_cancelled(step, **additional_context)
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
    end
  end
end
