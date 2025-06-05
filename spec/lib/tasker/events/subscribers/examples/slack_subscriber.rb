# frozen_string_literal: true

# SlackSubscriber demonstrates team communication integration with Slack
#
# This example shows how developers can integrate Tasker events with Slack for:
# - Rich message formatting with attachments and fields
# - Environment-appropriate channel routing
# - Visual indicators (emojis, colors) for quick recognition
# - Actionable notifications with buttons and links
# - Professional team communication patterns
#
# Usage:
#   SlackSubscriber.subscribe(Tasker::Events::Publisher.instance)
#
# Real implementation would replace logging with:
#   SlackWebhook.send(webhook_url, message)
#
class SlackSubscriber < Tasker::Events::Subscribers::BaseSubscriber
  subscribe_to 'task.completed', 'task.failed', 'workflow.completed'

  # Handle task completion events with success notifications
  #
  # @param event [Hash] Event payload containing task completion information
  # @return [void]
  def handle_task_completed(event)
    task_id = safe_get(event, :task_id)
    task_name = safe_get(event, :task_name, 'Unknown Task')
    execution_duration = safe_get(event, :execution_duration, 0)
    total_steps = safe_get(event, :total_steps, 0)
    completed_steps = safe_get(event, :completed_steps, 0)

    message = {
      channel: channel_for_success_notifications,
      username: 'Tasker Bot',
      icon_emoji: ':white_check_mark:',
      text: 'Task completed successfully! 🎉',
      attachments: [
        {
          color: 'good',
          title: "#{task_name} (#{task_id})",
          title_link: task_url(task_id),
          fields: [
            {
              title: 'Duration',
              value: format_duration(execution_duration),
              short: true
            },
            {
              title: 'Steps',
              value: "#{completed_steps}/#{total_steps}",
              short: true
            },
            {
              title: 'Completed At',
              value: safe_get(event, :timestamp, Time.current).strftime('%Y-%m-%d %H:%M:%S'),
              short: true
            },
            {
              title: 'Environment',
              value: Rails.env.capitalize,
              short: true
            }
          ],
          footer: 'Tasker Workflow Engine',
          ts: safe_get(event, :timestamp, Time.current).to_i
        }
      ]
    }

    # In real implementation: SlackWebhook.send(webhook_url, message)
    Rails.logger.info "[SLACK] Task completion: #{message}"
  end

  # Handle task failure events with detailed error information
  #
  # @param event [Hash] Event payload containing task failure information
  # @return [void]
  def handle_task_failed(event)
    task_id = safe_get(event, :task_id)
    task_name = safe_get(event, :task_name, 'Unknown Task')
    error_message = safe_get(event, :error_message, 'Unknown error')
    failed_steps = safe_get(event, :failed_steps, 0)
    total_steps = safe_get(event, :total_steps, 0)

    message = {
      channel: channel_for_alerts,
      username: 'Tasker Bot',
      icon_emoji: ':x:',
      text: 'Task failed - requires attention ⚠️',
      attachments: [
        {
          color: 'danger',
          title: "#{task_name} (#{task_id})",
          title_link: task_url(task_id),
          fields: [
            {
              title: 'Error',
              value: truncate_error_message(error_message),
              short: false
            },
            {
              title: 'Failed Steps',
              value: "#{failed_steps}/#{total_steps}",
              short: true
            },
            {
              title: 'Failed At',
              value: safe_get(event, :timestamp, Time.current).strftime('%Y-%m-%d %H:%M:%S'),
              short: true
            }
          ],
          actions: [
            {
              type: 'button',
              text: 'View Task Details',
              url: task_url(task_id),
              style: 'primary'
            },
            {
              type: 'button',
              text: 'Retry Task',
              url: retry_task_url(task_id),
              style: 'default'
            }
          ],
          footer: 'Tasker Workflow Engine',
          ts: safe_get(event, :timestamp, Time.current).to_i
        }
      ]
    }

    # In real implementation: SlackWebhook.send(webhook_url, message)
    Rails.logger.error "[SLACK] Task failure: #{message}"
  end

  # Handle workflow completion events with summary statistics
  #
  # @param event [Hash] Event payload containing workflow completion information
  # @return [void]
  def handle_workflow_completed(event)
    workflow_id = safe_get(event, :workflow_id)
    workflow_name = safe_get(event, :workflow_name, 'Workflow')
    total_steps = safe_get(event, :total_steps, 0)
    total_duration = safe_get(event, :total_duration, 0)
    success_rate = safe_get(event, :success_rate, 100)

    emoji = if success_rate >= 95
              ':tada:'
            else
              success_rate >= 80 ? ':white_check_mark:' : ':warning:'
            end
    color = if success_rate >= 95
              'good'
            else
              success_rate >= 80 ? 'good' : 'warning'
            end

    {
      channel: channel_for_success_notifications,
      username: 'Tasker Bot',
      icon_emoji: emoji,
      text: "Workflow batch completed! #{emoji}",
      attachments: [
        {
          color: color,
          title: "#{workflow_name} Batch",
          fields: [
            {
              title: 'Total Steps',
              value: total_steps.to_s,
              short: true
            },
            {
              title: 'Success Rate',
              value: "#{success_rate.round(1)}%",
              short: true
            },
            {
              title: 'Total Duration',
              value: format_duration(total_duration),
              short: true
            },
            {
              title: 'Environment',
              value: Rails.env.capitalize,
              short: true
            }
          ],
          footer: 'Tasker Workflow Engine',
          ts: safe_get(event, :timestamp, Time.current).to_i
        }
      ]
    }

    # In real implementation: SlackWebhook.send(webhook_url, message)
    Rails.logger.info "[SLACK] Workflow #{workflow_id} completed with #{total_steps} steps"
  end

  private

  # Get Slack channel for success notifications based on environment
  #
  # @return [String] Slack channel name
  def channel_for_success_notifications
    case Rails.env
    when 'production'
      '#tasker-production'
    when 'staging'
      '#tasker-staging'
    else
      '#tasker-dev'
    end
  end

  # Get Slack channel for alerts and failures
  #
  # @return [String] Slack channel name
  def channel_for_alerts
    case Rails.env
    when 'production'
      '#tasker-alerts'
    when 'staging'
      '#tasker-staging-alerts'
    else
      '#tasker-dev'
    end
  end

  # Format duration in human-readable format
  #
  # @param seconds [Float] Duration in seconds
  # @return [String] Formatted duration
  def format_duration(seconds)
    return '0s' if seconds.nil? || seconds <= 0

    if seconds < 60
      "#{seconds.round(1)}s"
    elsif seconds < 3600
      minutes = (seconds / 60).round(1)
      "#{minutes}m"
    else
      hours = (seconds / 3600).round(1)
      "#{hours}h"
    end
  end

  # Truncate error messages for display in Slack
  #
  # @param message [String] Error message
  # @return [String] Truncated message
  def truncate_error_message(message)
    return message if message.length <= 200

    "#{message[0..197]}..."
  end

  # Generate URL for task details page
  #
  # @param task_id [String] Task identifier
  # @return [String] Task URL
  def task_url(task_id)
    # In real implementation, generate proper URL
    "#{base_url}/tasker/tasks/#{task_id}"
  end

  # Generate URL for task retry action
  #
  # @param task_id [String] Task identifier
  # @return [String] Retry URL
  def retry_task_url(task_id)
    # In real implementation, generate proper retry URL
    "#{base_url}/tasker/tasks/#{task_id}/retry"
  end

  # Get base URL for the application
  #
  # @return [String] Base URL
  def base_url
    # In real implementation, use proper URL generation
    case Rails.env
    when 'production'
      'https://app.example.com'
    when 'staging'
      'https://staging.example.com'
    else
      'http://localhost:3000'
    end
  end
end
