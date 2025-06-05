# frozen_string_literal: true

# PagerDutySubscriber demonstrates critical alerting integration with PagerDuty
#
# This example shows how developers can integrate Tasker events with PagerDuty for:
# - Filtered alerting based on business logic (critical vs non-critical tasks)
# - Proper incident formatting for PagerDuty's Events API v2
# - Deduplication keys to prevent alert spam
# - Environment-appropriate routing and escalation
#
# Usage:
#   PagerDutySubscriber.subscribe(Tasker::Events::Publisher.instance)
#
# Real implementation would replace logging with:
#   PagerDuty::Incident.trigger(alert_data)
#
class PagerDutySubscriber < Tasker::Events::Subscribers::BaseSubscriber
  subscribe_to 'task.failed', 'workflow.error'

  # Handle task failure events with criticality-based alerting
  #
  # @param event [Hash] Event payload containing task failure information
  # @return [void]
  def handle_task_failed(event)
    task_id = safe_get(event, :task_id)
    error_message = safe_get(event, :error_message, 'Task execution failed')

    # Only alert on critical tasks (business logic filtering)
    return unless critical_task?(task_id)

    # Format incident data for PagerDuty Events API v2
    alert_data = {
      routing_key: routing_key_for_environment,
      event_action: 'trigger',
      dedup_key: "tasker-task-#{task_id}",
      payload: {
        summary: "Critical Tasker task failed: #{task_id}",
        severity: determine_severity(event),
        source: 'tasker-engine',
        component: safe_get(event, :task_name, 'unknown'),
        group: 'workflow-engine',
        custom_details: {
          task_id: task_id,
          task_name: safe_get(event, :task_name),
          error_message: error_message,
          execution_status: safe_get(event, :execution_status),
          total_steps: safe_get(event, :total_steps),
          completed_steps: safe_get(event, :completed_steps),
          failed_at: safe_get(event, :timestamp, Time.current),
          environment: Rails.env
        }
      }
    }

    # In real implementation: PagerDuty::Incident.trigger(alert_data)
    Rails.logger.error "[PAGERDUTY] Critical alert: #{alert_data}"
  end

  # Handle workflow-level errors with immediate escalation
  #
  # @param event [Hash] Event payload containing workflow error information
  # @return [void]
  def handle_workflow_error(event)
    workflow_id = safe_get(event, :workflow_id)
    error_message = safe_get(event, :error_message, 'Workflow system error')

    # Workflow errors always escalate immediately
    alert_data = {
      routing_key: routing_key_for_environment,
      event_action: 'trigger',
      dedup_key: "tasker-workflow-error-#{workflow_id}",
      payload: {
        summary: "Critical workflow system error: #{workflow_id}",
        severity: 'critical',
        source: 'tasker-engine',
        component: 'workflow-orchestrator',
        group: 'system-critical',
        custom_details: {
          workflow_id: workflow_id,
          error_message: error_message,
          error_type: safe_get(event, :error_type, 'system'),
          affected_components: safe_get(event, :affected_components, []),
          timestamp: safe_get(event, :timestamp, Time.current),
          environment: Rails.env
        }
      }
    }

    # In real implementation: PagerDuty::Incident.trigger(alert_data)
    Rails.logger.error "[PAGERDUTY] Workflow error escalation: #{alert_data}"
  end

  private

  # Determine if a task should trigger critical alerts
  #
  # @param task_id [String] The task identifier
  # @return [Boolean] true if task is critical
  def critical_task?(task_id)
    # Example business logic for determining criticality
    # In real implementation, this might:
    # - Query the task record for priority flags
    # - Check task name patterns
    # - Examine task metadata or tags
    # - Consult external configuration

    return true if task_id.include?('critical')
    return true if task_id.include?('production')
    return true if task_id.include?('payment')
    return true if task_id.include?('order')

    # Could also check based on task configuration
    # task = Task.find_by(task_id: task_id)
    # task&.priority == 'critical' || task&.tags&.include?('alert-on-failure')

    false
  end

  # Determine incident severity based on event characteristics
  #
  # @param event [Hash] Event payload
  # @return [String] PagerDuty severity level
  def determine_severity(event)
    error_type = safe_get(event, :error_type, 'unknown')
    task_name = safe_get(event, :task_name, '')

    # Business logic for severity assignment
    return 'critical' if task_name.include?('payment')
    return 'critical' if error_type == 'data_corruption'
    return 'error' if error_type == 'timeout'
    return 'warning' if error_type == 'retry_exhausted'

    'error' # Default severity
  end

  # Get appropriate routing key based on environment
  #
  # @return [String] PagerDuty integration routing key
  def routing_key_for_environment
    case Rails.env
    when 'production'
      'tasker-production-critical-failures'
    when 'staging'
      'tasker-staging-failures'
    else
      'tasker-development-failures'
    end
  end
end
