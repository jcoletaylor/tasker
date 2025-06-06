# frozen_string_literal: true

module Tasker
  module Events
    # EventPayloadBuilder creates standardized event payloads for consistent telemetry
    #
    # This class solves the payload standardization issues identified during factory migration:
    # - Missing :execution_duration keys in step completion events
    # - Missing :error_message keys in step failure events
    # - Missing :attempt_number keys for retry tracking
    # - Inconsistent payload structure across different event publishers
    #
    # Usage:
    #   payload = EventPayloadBuilder.build_step_payload(step, task, event_type: :completed)
    #   Tasker::Events::Publisher.instance.publish('step.completed', payload)
    class EventPayloadBuilder
      class << self
        # Build standardized payload for step events
        #
        # @param step [WorkflowStep] The step object
        # @param task [Task] The associated task
        # @param event_type [Symbol] The type of event (:started, :completed, :failed, :retry, etc.)
        # @param additional_context [Hash] Additional context to merge in
        # @return [Hash] Standardized event payload
        def build_step_payload(step, task = nil, event_type: :completed, additional_context: {})
          task ||= step.task

          base_payload = {
            # Core identifiers (always present)
            task_id: task.task_id,
            step_id: step.workflow_step_id,
            step_name: step.name,

            # Timing information - steps use last_attempted_at and processed_at
            started_at: step.last_attempted_at&.iso8601,
            completed_at: step.processed_at&.iso8601,

            # Retry and attempt tracking
            attempt_number: step.attempts || 1,
            retry_limit: step.retry_limit,

            # Event metadata
            event_type: event_type.to_s,
            timestamp: Time.current.iso8601
          }

          # Add event-specific fields
          case event_type
          when :completed
            base_payload.merge!(build_completion_payload(step))
          when :failed
            base_payload.merge!(build_failure_payload(step, additional_context))
          when :started
            base_payload.merge!(build_start_payload(step))
          when :retry
            base_payload.merge!(build_retry_payload(step))
          end

          # Merge additional context, allowing overrides
          base_payload.merge!(additional_context)

          base_payload
        end

        # Build standardized payload for task events
        #
        # @param task [Task] The task object
        # @param event_type [Symbol] The type of event (:started, :completed, :failed, etc.)
        # @param additional_context [Hash] Additional context to merge in
        # @return [Hash] Standardized event payload
        def build_task_payload(task, event_type: :completed, additional_context: {})
          # Get all completion stats in a single optimized query
          stats = Tasker::WorkflowStep.task_completion_stats(task)

          base_payload = {
            # Core identifiers
            task_id: task.task_id,
            task_name: get_task_name(task),

            # Timing information - only set completed_at for fully completed tasks
            started_at: task.created_at&.iso8601,
            completed_at: stats[:all_complete] ? stats[:latest_completion_time]&.iso8601 : nil,

            # Task metadata
            task_type: task.class.name,
            event_type: event_type.to_s,
            timestamp: Time.current.iso8601
          }

          # Add duration and step statistics to all task events
          base_payload.merge!(build_task_timing_and_statistics(task, stats))

          # Add event-specific fields
          case event_type
          when :completed
            base_payload.merge!(build_task_completion_specific_payload(task))
          when :failed
            base_payload.merge!(build_task_failure_payload(task, additional_context))
          when :started
            base_payload.merge!(build_task_start_payload(task))
          end

          # Merge additional context, allowing overrides
          base_payload.merge!(additional_context)

          base_payload
        end

        # Build standardized payload for workflow orchestration events
        #
        # @param event_type [Symbol] The orchestration event type
        # @param context [Hash] The orchestration context
        # @return [Hash] Standardized orchestration payload
        def build_orchestration_payload(event_type:, context: {})
          {
            # Event metadata
            event_type: event_type.to_s,
            orchestration_event: true,
            timestamp: Time.current.iso8601,

            # Merge provided context
            **context
          }
        end

        private

        # Get task name safely handling the named_task association
        #
        # @param task [Task] The task object
        # @return [String] The task name
        def get_task_name(task)
          if task.respond_to?(:named_task) && task.named_task
            task.named_task.name
          elsif task.respond_to?(:name)
            task.name
          else
            'unknown_task'
          end
        end

        # Build completion-specific payload fields
        #
        # @param step [WorkflowStep] The completed step
        # @return [Hash] Completion payload fields
        def build_completion_payload(step)
          payload = {}

          # Calculate execution duration using last_attempted_at and processed_at
          payload[:execution_duration] = if step.last_attempted_at && step.processed_at
                                           (step.processed_at - step.last_attempted_at).round(3)
                                         else
                                           0.0
                                         end

          # Include step results if available
          payload[:step_results] = step.results if step.results.present?

          payload
        end

        # Build failure-specific payload fields
        #
        # @param step [WorkflowStep] The failed step
        # @param additional_context [Hash] Additional context (may include error details)
        # @return [Hash] Failure payload fields
        def build_failure_payload(step, additional_context = {})
          payload = {}

          # Extract error information from step results or additional context
          error_info = extract_error_info(step, additional_context)
          payload.merge!(error_info)

          # Include step results
          payload[:step_results] = step.results if step.results.present?

          payload
        end

        # Build start-specific payload fields
        #
        # @param step [WorkflowStep] The starting step
        # @return [Hash] Start payload fields
        def build_start_payload(step)
          {
            step_inputs: step.inputs,
            step_dependencies: step.respond_to?(:parents) ? step.parents.map(&:name) : []
          }
        end

        # Build retry-specific payload fields
        #
        # @param step [WorkflowStep] The step being retried
        # @return [Hash] Retry payload fields
        def build_retry_payload(step)
          {
            previous_attempts: step.attempts - 1,
            retry_reason: 'Step execution failed',
            backoff_strategy: 'exponential' # Could be made configurable
          }
        end

        # Build task timing and statistics (shared across all task event types)
        #
        # @param task [Task] The task
        # @param stats [Hash] Pre-calculated task completion statistics from WorkflowStep.task_completion_stats
        # @return [Hash] Timing and statistics payload fields
        def build_task_timing_and_statistics(task, stats)
          payload = {}

          # Distinguish between total duration (all steps complete) and current duration (in progress)
          if stats[:all_complete] && task.created_at && stats[:latest_completion_time]
            # True total execution duration - complete workflow
            payload[:total_execution_duration] = (stats[:latest_completion_time] - task.created_at).round(3)
            payload[:current_execution_duration] = nil # Not applicable for completed tasks
          elsif task.created_at
            # Current execution duration - task still in progress
            payload[:total_execution_duration] = nil # Not available until completion
            payload[:current_execution_duration] = (Time.current - task.created_at).round(3)
          else
            # No timing information available
            payload[:total_execution_duration] = nil
            payload[:current_execution_duration] = nil
          end

          # Use pre-calculated step statistics (no additional queries needed)
          payload[:total_steps] = stats[:total_steps]
          payload[:completed_steps] = stats[:completed_steps]
          payload[:failed_steps] = stats[:failed_steps]
          payload[:pending_steps] = stats[:pending_steps]

          payload
        end

        # Build task completion-specific payload fields (only for completed events)
        #
        # @param task [Task] The completed task
        # @return [Hash] Completion-specific payload fields
        def build_task_completion_specific_payload(_task)
          {
            # Could add completion-specific metadata here if needed
            # For now, all the important data is in the timing/statistics method
          }
        end

        # Build task failure payload fields
        #
        # @param task [Task] The failed task
        # @param additional_context [Hash] Additional context
        # @return [Hash] Task failure payload fields
        def build_task_failure_payload(_task, additional_context = {})
          payload = {}

          # Extract error information
          if additional_context[:error_steps].present?
            payload[:error_steps] = additional_context[:error_steps]
            payload[:error_step_results] = additional_context[:error_step_results]
          end

          # Default error message if not provided
          payload[:error_message] = additional_context[:error_message] ||
                                    additional_context[:error] ||
                                    'Task execution failed'

          payload
        end

        # Build task start payload fields
        #
        # @param task [Task] The starting task
        # @return [Hash] Task start payload fields
        def build_task_start_payload(task)
          {
            task_context: task.context,
            total_steps: task.workflow_steps.count
          }
        end

        # Extract error information from step and context
        #
        # @param step [WorkflowStep] The step with error
        # @param additional_context [Hash] Additional context
        # @return [Hash] Error information payload
        def extract_error_info(step, additional_context = {})
          error_payload = {}

          # Primary error message (standardized key for TelemetrySubscriber)
          error_payload[:error_message] = additional_context[:error_message] ||
                                          additional_context[:error] ||
                                          step.results&.dig('error') ||
                                          step.results&.dig(:error) ||
                                          'Unknown error'

          # Exception class if available
          error_payload[:exception_class] = if additional_context[:exception_object]
                                              additional_context[:exception_object].class.name
                                            elsif additional_context[:exception_class]
                                              additional_context[:exception_class]
                                            else
                                              'StandardError'
                                            end

          # Backtrace if available
          if additional_context[:backtrace]
            error_payload[:backtrace] = additional_context[:backtrace]
          elsif step.results&.dig('backtrace')
            error_payload[:backtrace] = step.results['backtrace']
          elsif step.results&.dig(:backtrace)
            error_payload[:backtrace] = step.results[:backtrace]
          end

          error_payload
        end

        # Check if a step is complete (reused from various helpers)
        #
        # @param step [WorkflowStep] The step to check
        # @return [Boolean] True if step is complete
        def step_complete?(step)
          [
            Tasker::Constants::WorkflowStepStatuses::COMPLETE,
            Tasker::Constants::WorkflowStepStatuses::RESOLVED_MANUALLY
          ].include?(step.status)
        end

        # Check if a step is in error state
        #
        # @param step [WorkflowStep] The step to check
        # @return [Boolean] True if step is in error
        def step_in_error?(step)
          step.status == Tasker::Constants::WorkflowStepStatuses::ERROR
        end
      end
    end
  end
end
