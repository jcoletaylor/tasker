# frozen_string_literal: true

module BlogExamples
  module Post04
    module StepHandlers
      class NotifyCustomerHandler < Tasker::StepHandler::Base
        def process(task, sequence, step)
          # Extract and validate inputs using our gold standard pattern
          inputs = extract_and_validate_inputs(task.context, step, sequence)

          # Mock call to notification service for blog examples
          {
            customer_email: inputs[:customer_email],
            payment_id: inputs[:payment_id],
            refund_id: inputs[:refund_id],
            refund_amount: inputs[:refund_amount],
            template: 'refund_confirmation',
            namespace: 'payments'
          }

          # Mock notification service call - in reality this would send email/SMS
          notification_result = {
            notification_sent: true,
            notification_id: "notif_#{SecureRandom.hex(8)}",
            channel: 'email',
            customer_email: inputs[:customer_email],
            sent_at: Time.current.iso8601
          }

          # Validate the notification was sent
          ensure_notification_sent!(notification_result)
          notification_result
        end

        def process_results(step, notification_result, _initial_results)
          # Safe result processing - format the notification results
          step.results = {
            customer_notified: true,
            notification_id: notification_result[:notification_id],
            notification_channel: notification_result[:channel],
            customer_email: notification_result[:customer_email],
            sent_timestamp: notification_result[:sent_at],
            namespace: 'payments'
          }
        rescue StandardError => e
          # If result processing fails, don't retry the API call
          raise Tasker::PermanentError,
                "Failed to process notification results: #{e.message}"
        end

        private

        def extract_and_validate_inputs(context, _step, sequence)
          # Normalize context to symbols early
          normalized_context = context.deep_symbolize_keys

          # Get payment record update results from previous step
          records_step = sequence.find_step_by_name('update_payment_records')
          records_results = records_step&.results&.deep_symbolize_keys

          unless records_results&.dig(:records_updated)
            raise Tasker::PermanentError,
                  'Payment records must be updated before notifying customer'
          end

          # Get customer email from context - in reality this might come from a customer lookup
          customer_email = normalized_context[:customer_email]
          unless customer_email
            raise Tasker::PermanentError,
                  'Customer email is required for notification'
          end

          {
            customer_email: customer_email,
            payment_id: records_results[:payment_id],
            refund_id: records_results[:refund_id],
            refund_amount: normalized_context[:refund_amount]
          }
        end

        def ensure_notification_sent!(notification_result)
          unless notification_result[:notification_sent]
            raise Tasker::RetryableError,
                  'Customer notification failed, will retry'
          end

          return if notification_result[:notification_id]

          raise Tasker::PermanentError,
                'Notification sent but no tracking ID returned'
        end
      end
    end
  end
end
