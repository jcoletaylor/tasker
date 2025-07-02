module BlogExamples
  module Post01
    module StepHandlers
      class SendConfirmationHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        order_result = step_results(sequence, 'create_order')
        customer_info = task.context['customer_info']
        cart_validation = step_results(sequence, 'validate_cart')

        order_id = order_result['order_id']
        order_number = order_result['order_number']

        # Prepare email data
        email_data = {
          to: customer_info['email'],
          customer_name: customer_info['name'],
          order_number: order_number,
          order_id: order_id,
          total_amount: order_result['total_amount'],
          estimated_delivery: order_result['estimated_delivery'],
          items: cart_validation['validated_items'],
          order_url: "https://example.com/orders/#{order_id}"
        }

        # Send confirmation email using mock service for blog validation
        begin
          delivery_result = MockEmailService.send_confirmation(**email_data)

          # Note: In a real implementation, you would log to EmailLog model
          # For this blog example, we'll skip the audit logging to avoid additional dependencies
          # EmailLog.create!(order_id: order_id, email_type: 'order_confirmation', ...)

          {
            email_sent: true,
            recipient: customer_info['email'],
            email_type: 'order_confirmation',
            sent_at: Time.current.iso8601,
            message_id: delivery_result[:message_id] || "mock_#{SecureRandom.hex(8)}"
          }
        # Note: In a production environment, you would handle specific SMTP errors:
        # rescue Net::SMTPServerBusy, Net::SMTPFatalError, Net::SMTPAuthenticationError, Timeout::Error
        # For this blog example, we'll use generic error handling to avoid dependency issues
        rescue StandardError => e
          # Log the error for debugging
          Rails.logger.error "Email delivery error: #{e.class} - #{e.message}"

          # Most email errors are retryable - let step configuration handle retries
          raise StandardError, "Email delivery failed: #{e.message}"
        end
      end

      private

      def step_results(sequence, step_name)
        step = sequence.steps.find { |s| s.name == step_name }
        step&.results || {}
      end
      end
    end
  end
end
