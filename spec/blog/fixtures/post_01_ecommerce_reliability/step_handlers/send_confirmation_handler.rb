# frozen_string_literal: true

module BlogExamples
  module Post01
    module StepHandlers
      class SendConfirmationHandler < Tasker::StepHandler::Base
        def process(task, sequence, step)
          # Extract and validate all required inputs
          email_inputs = extract_and_validate_inputs(task, sequence, step)

          Rails.logger.info "Sending confirmation email: task_id=#{task.task_id}, recipient=#{email_inputs[:customer_info][:email]}"

          # Send confirmation email - this is the core integration
          begin
            send_confirmation_email(email_inputs)

            # Return raw email sending results for process_results to handle
          rescue StandardError => e
            Rails.logger.error "Email sending failed: #{e.message}"
            raise
          end
        end

        # Override process_results to handle business logic and result formatting
        def process_results(step, email_response, _initial_results)
          # At this point we know the email sending succeeded
          # Now safely format the business results

          delivery_result = email_response[:delivery_result]
          customer_email = email_response[:customer_email]

          Rails.logger.info "Confirmation email sent successfully: recipient=#{customer_email}"

          step.results = {
            email_sent: true,
            recipient: customer_email,
            email_type: 'order_confirmation',
            sent_at: Time.current.iso8601,
            message_id: delivery_result[:message_id] || "mock_#{SecureRandom.hex(8)}"
          }
        rescue StandardError => e
          # If result processing fails, we don't want to retry the email sending
          # Log the error and set a failure result without retrying
          Rails.logger.error "Failed to process email sending results: #{e.message}"
          step.results = {
            error: true,
            error_message: "Email sending succeeded but result processing failed: #{e.message}",
            error_code: 'RESULT_PROCESSING_FAILED',
            raw_email_response: email_response,
            status: 'processing_error'
          }
        end

        private

        # Extract and validate all required inputs for email sending
        def extract_and_validate_inputs(task, sequence, _step)
          # Normalize all hash keys to symbols for consistent access
          customer_info = task.context['customer_info']&.deep_symbolize_keys
          order_result = step_results(sequence, 'create_order')&.deep_symbolize_keys
          cart_validation = step_results(sequence, 'validate_cart')&.deep_symbolize_keys

          unless customer_info&.dig(:email)
            raise Tasker::PermanentError.new(
              'Customer email is required but was not provided',
              error_code: 'MISSING_CUSTOMER_EMAIL'
            )
          end

          unless order_result&.dig(:order_id)
            raise Tasker::PermanentError.new(
              'Order results are required but were not found from create_order step',
              error_code: 'MISSING_ORDER_RESULT'
            )
          end

          unless cart_validation&.dig(:validated_items)&.any?
            raise Tasker::PermanentError.new(
              'Cart validation results are required but were not found from validate_cart step',
              error_code: 'MISSING_CART_VALIDATION'
            )
          end

          {
            customer_info: customer_info,
            order_result: order_result,
            cart_validation: cart_validation
          }
        end

        # Send confirmation email using validated inputs
        def send_confirmation_email(email_inputs)
          customer_info = email_inputs[:customer_info]
          order_result = email_inputs[:order_result]
          cart_validation = email_inputs[:cart_validation]

          # Prepare email data
          email_data = {
            to: customer_info[:email],
            customer_name: customer_info[:name],
            order_number: order_result[:order_number],
            order_id: order_result[:order_id],
            total_amount: order_result[:total_amount],
            estimated_delivery: order_result[:estimated_delivery],
            items: cart_validation[:validated_items],
            order_url: "https://example.com/orders/#{order_result[:order_id]}"
          }

          # Send confirmation email using mock service for blog validation
          delivery_result = MockEmailService.send_confirmation(**email_data)

          # Ensure email was sent successfully
          ensure_email_sent_successfully!(delivery_result)

          {
            delivery_result: delivery_result,
            customer_email: customer_info[:email],
            email_data: email_data,
            sent_timestamp: Time.current.iso8601
          }
        end

        # Ensure email was sent successfully, handling different error types
        def ensure_email_sent_successfully!(delivery_result)
          case delivery_result[:status]
          when 'sent', 'delivered'
            # Success - continue processing
            nil
          when 'rate_limited'
            # Temporary issue - can be retried
            raise Tasker::RetryableError.new(
              'Email service rate limited',
              retry_after: 60
            )
          when 'service_unavailable', 'timeout'
            # Temporary service issues - can be retried
            raise Tasker::RetryableError, 'Email service temporarily unavailable'
          when 'invalid_email'
            # Permanent issue - bad email address
            raise Tasker::PermanentError.new(
              'Invalid email address provided',
              error_code: 'INVALID_EMAIL'
            )
          else
            # Unknown status or generic error - treat as retryable for email delivery
            error_message = delivery_result[:error] || 'Unknown email delivery error'
            raise Tasker::RetryableError, "Email delivery failed: #{error_message}"
          end
        end

        def step_results(sequence, step_name)
          step = sequence.steps.find { |s| s.name == step_name }
          step&.results || {}
        end
      end
    end
  end
end
