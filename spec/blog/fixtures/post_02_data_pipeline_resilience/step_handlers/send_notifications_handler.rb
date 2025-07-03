# frozen_string_literal: true

module BlogExamples
  module Post02
    module StepHandlers
      class SendNotificationsHandler < Tasker::StepHandler::Base
        def process(task, sequence, step)
          # Extract and validate all required inputs
          notification_inputs = extract_and_validate_inputs(task, sequence, step)

          Rails.logger.info "Starting notification delivery: task_id=#{task.task_id}"

          # Send notifications - this is the core integration
          begin
            send_pipeline_notifications(notification_inputs)

            # Return raw notification results for process_results to handle
          rescue StandardError => e
            Rails.logger.error "Notification delivery failed: #{e.message}"
            raise
          end
        end

        # Override process_results to handle business logic and result formatting
        def process_results(step, notification_response, _initial_results)
          # At this point we know the notification sending succeeded
          # Now safely format the business results

          notification_channels = notification_response[:notification_channels]

          Rails.logger.info "Notifications sent successfully to #{notification_channels.length} channels"

          step.results = {
            notifications_sent: notification_response[:data],
            notification_metadata: notification_response[:metadata],
            sent_at: Time.current.iso8601
          }
        rescue StandardError => e
          # If result processing fails, we don't want to retry the notification sending
          # Log the error and set a failure result without retrying
          Rails.logger.error "Failed to process notification sending results: #{e.message}"
          step.results = {
            error: true,
            error_message: "Notification sending succeeded but result processing failed: #{e.message}",
            error_code: 'RESULT_PROCESSING_FAILED',
            raw_notification_response: notification_response,
            status: 'processing_error'
          }
        end

        private

        # Extract and validate all required inputs for notification sending
        def extract_and_validate_inputs(task, sequence, _step)
          # Get insights and notification channels from task context with normalized keys
          insights_step = get_dependent_step(sequence, 'generate_insights')
          insights = insights_step&.results&.deep_symbolize_keys&.dig(:insights)

          task_context = task.context.deep_symbolize_keys
          notification_channels = task_context[:notification_channels] || ['#data-team']

          unless insights
            raise Tasker::PermanentError.new(
              'Insights data is required but was not found from generate_insights step',
              error_code: 'MISSING_INSIGHTS_DATA'
            )
          end

          unless notification_channels&.any?
            raise Tasker::PermanentError.new(
              'At least one notification channel is required',
              error_code: 'MISSING_NOTIFICATION_CHANNELS'
            )
          end

          {
            insights: insights,
            notification_channels: notification_channels,
            task_context: task_context
          }
        end

        # Send pipeline notifications using validated inputs
        def send_pipeline_notifications(notification_inputs)
          # Use mock dashboard service for notifications
          result = MockDashboardService.send_notifications(
            notification_channels: notification_inputs[:notification_channels],
            insights: notification_inputs[:insights],
            timeout_seconds: 10 # Default timeout for notifications
          )

          # Add notification channels to result for logging
          result.merge(notification_channels: notification_inputs[:notification_channels])
        rescue MockDashboardService::TimeoutError => e
          # Temporary failure - can be retried
          raise Tasker::RetryableError, "Notification sending timed out: #{e.message}"
        rescue MockDashboardService::ConnectionError => e
          # Temporary failure - connection issues
          raise Tasker::RetryableError, "Notification service connection error: #{e.message}"
        rescue MockDashboardService::RateLimitedError => e
          # Temporary failure - rate limited
          raise Tasker::RetryableError.new(
            "Notification service rate limited: #{e.message}",
            retry_after: 60
          )
        rescue MockDashboardService::InvalidChannelError => e
          # Permanent failure - invalid notification channels
          raise Tasker::PermanentError.new(
            "Invalid notification channels: #{e.message}",
            error_code: 'INVALID_NOTIFICATION_CHANNELS'
          )
        end

        def get_dependent_step(sequence, step_name)
          sequence.steps.find { |s| s.name == step_name }
        end
      end
    end
  end
end
