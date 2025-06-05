# frozen_string_literal: true

# SentrySubscriber demonstrates error tracking integration with Sentry
#
# This example shows how developers can integrate Tasker events with Sentry for:
# - Comprehensive error tracking across task and step failures
# - Intelligent error grouping using fingerprinting
# - Rich context and tagging for debugging
# - Appropriate severity levels for different error types
#
# Usage:
#   SentrySubscriber.subscribe(Tasker::Events::Publisher.instance)
#
# Real implementation would replace logging with:
#   Sentry.capture_message(error_message, **sentry_data)
#
class SentrySubscriber < Tasker::Events::Subscribers::BaseSubscriber
  subscribe_to 'task.failed', 'step.failed', 'workflow.error'

  # Handle task failure events with comprehensive error tracking
  #
  # @param event [Hash] Event payload containing task failure information
  # @return [void]
  def handle_task_failed(event)
    task_id = safe_get(event, :task_id)
    error_message = safe_get(event, :error_message, 'Unknown error')

    # Format data for Sentry error tracking
    sentry_data = {
      level: 'error',
      fingerprint: ['tasker', 'task_failed', task_id],
      tags: {
        task_id: task_id,
        component: 'tasker',
        environment: Rails.env
      },
      extra: {
        error_message: error_message,
        timestamp: safe_get(event, :timestamp, Time.current),
        execution_status: safe_get(event, :execution_status),
        total_steps: safe_get(event, :total_steps),
        completed_steps: safe_get(event, :completed_steps)
      }
    }

    # In real implementation: Sentry.capture_message(error_message, **sentry_data)
    Rails.logger.error "[SENTRY] Task failed: #{sentry_data}"
  end

  # Handle step failure events with step-specific context
  #
  # @param event [Hash] Event payload containing step failure information
  # @return [void]
  def handle_step_failed(event)
    step_id = safe_get(event, :step_id)
    task_id = safe_get(event, :task_id)
    error_message = safe_get(event, :error_message, 'Step execution failed')

    # Format data for Sentry with step context
    sentry_data = {
      level: 'warning',
      fingerprint: ['tasker', 'step_failed', step_id],
      tags: {
        task_id: task_id,
        step_id: step_id,
        step_name: safe_get(event, :step_name),
        component: 'tasker',
        environment: Rails.env
      },
      extra: {
        error_message: error_message,
        attempt_number: safe_get(event, :attempt_number, 1),
        retry_limit: safe_get(event, :retry_limit),
        execution_duration: safe_get(event, :execution_duration),
        timestamp: safe_get(event, :timestamp, Time.current)
      }
    }

    # In real implementation: Sentry.capture_message(error_message, **sentry_data)
    Rails.logger.warn "[SENTRY] Step failed: #{sentry_data}"
  end

  # Handle broad workflow errors requiring immediate attention
  #
  # @param event [Hash] Event payload containing workflow error information
  # @return [void]
  def handle_workflow_error(event)
    workflow_id = safe_get(event, :workflow_id)
    safe_get(event, :error_message, 'Workflow error')

    sentry_data = {
      level: 'error',
      fingerprint: %w[tasker workflow_error],
      tags: {
        workflow_id: workflow_id,
        component: 'tasker',
        environment: Rails.env
      },
      extra: event
    }

    # In real implementation: Sentry.capture_message(error_message, **sentry_data)
    Rails.logger.error "[SENTRY] Workflow error: #{sentry_data}"
  end
end
