# frozen_string_literal: true

module BlogExamples
  module Post01
    module StepHandlers
      class ProcessPaymentHandler < Tasker::StepHandler::Base
        def process(task, sequence, step)
          # Extract and validate all required inputs
          payment_inputs = extract_and_validate_inputs(task, sequence, step)

          Rails.logger.info "Processing payment: task_id=#{task.task_id}, amount=#{payment_inputs[:amount_to_charge]}"

          # Make the payment service call - this is the core integration
          begin
            result = MockPaymentService.process_payment(
              amount: payment_inputs[:amount_to_charge],
              method: payment_inputs[:payment_method],
              token: payment_inputs[:payment_token]
            )

            # Normalize result keys to symbols for consistent access
            normalized_result = result.deep_symbolize_keys

            # Ensure the payment was successful, handling different error types appropriately
            ensure_payment_successful!(normalized_result)

            # Return normalized result for process_results to handle
            normalized_result
          rescue MockPaymentService::ServiceError => e
            # Handle service-specific exceptions
            case e.error_code
            when 'NETWORK_ERROR', 'TIMEOUT'
              raise Tasker::RetryableError, "Payment service network error: #{e.message}"
            when 'INVALID_REQUEST', 'AUTHENTICATION_FAILED'
              raise Tasker::PermanentError.new(
                "Payment service configuration error: #{e.message}",
                error_code: e.error_code
              )
            else
              # Unknown service error - treat as retryable
              raise Tasker::RetryableError, "Payment service error: #{e.message}"
            end
          end
        end

        # Override process_results to handle business logic and result formatting
        def process_results(step, payment_service_response, _initial_results)
          # At this point we know the payment service call succeeded
          # Now safely extract and format the business results

          # payment_service_response is already symbolized from process() method
          payment_id = payment_service_response[:payment_id]
          amount_charged = payment_service_response[:amount_charged]

          Rails.logger.info "Payment processed successfully: payment_id=#{payment_id}, amount_charged=#{amount_charged}"

          step.results = {
            payment_id: payment_id,
            amount_charged: amount_charged,
            currency: payment_service_response[:currency] || 'USD',
            payment_method_type: payment_service_response[:payment_method_type] || 'credit_card',
            transaction_id: payment_service_response[:transaction_id],
            processed_at: Time.current.iso8601,
            status: 'completed'
          }
        rescue StandardError => e
          # If result processing fails, we don't want to retry the payment
          # Log the error and set a failure result without retrying
          Rails.logger.error "Failed to process payment results: #{e.message}"
          step.results = {
            error: true,
            error_message: "Payment succeeded but result processing failed: #{e.message}",
            error_code: 'RESULT_PROCESSING_FAILED',
            raw_payment_response: payment_service_response,
            status: 'processing_error'
          }
        end

        private

        # Extract and validate all required inputs for payment processing
        def extract_and_validate_inputs(task, sequence, _step)
          # Normalize all hash keys to symbols for consistent access
          payment_info = task.context['payment_info']&.deep_symbolize_keys
          cart_validation = step_results(sequence, 'validate_cart')&.deep_symbolize_keys

          # Early validation - throw PermanentError for missing required data
          payment_method = payment_info&.dig(:method)
          payment_token = payment_info&.dig(:token)
          amount_to_charge = cart_validation&.dig(:total)

          unless payment_method
            raise Tasker::PermanentError.new(
              'Payment method is required but was not provided',
              error_code: 'MISSING_PAYMENT_METHOD'
            )
          end

          unless payment_token
            raise Tasker::PermanentError.new(
              'Payment token is required but was not provided',
              error_code: 'MISSING_PAYMENT_TOKEN'
            )
          end

          unless amount_to_charge
            raise Tasker::PermanentError.new(
              'Cart total is required but was not found from validate_cart step',
              error_code: 'MISSING_CART_TOTAL'
            )
          end

          # Validate payment amount matches cart total
          expected_amount = BigDecimal(amount_to_charge.to_s)
          provided_amount = BigDecimal(payment_info[:amount].to_s)

          if provided_amount != expected_amount
            raise Tasker::PermanentError.new(
              "Payment amount mismatch. Expected: #{expected_amount}, Provided: #{provided_amount}",
              error_code: 'PAYMENT_AMOUNT_MISMATCH'
            )
          end

          {
            amount_to_charge: amount_to_charge,
            payment_method: payment_method,
            payment_token: payment_token,
            expected_amount: expected_amount,
            provided_amount: provided_amount
          }
        end

        # Ensure payment was successful, intelligently handling different error types
        def ensure_payment_successful!(payment_result)
          # payment_result is already symbolized from process() method
          case payment_result[:status]
          when 'succeeded'
            # Success - continue processing
            nil
          when 'insufficient_funds', 'card_declined', 'invalid_card'
            # These are permanent customer/card issues - don't retry
            error_message = payment_result[:error] || 'Payment declined'
            raise Tasker::PermanentError.new(
              "Payment declined: #{error_message}",
              error_code: 'PAYMENT_DECLINED'
            )
          when 'rate_limited'
            # Temporary issue - can be retried
            raise Tasker::RetryableError.new(
              'Payment service rate limited',
              retry_after: 30
            )
          when 'service_unavailable', 'timeout'
            # Temporary service issues - can be retried
            raise Tasker::RetryableError, 'Payment service temporarily unavailable'
          else
            # Unknown status - treat as retryable for safety
            error_message = payment_result[:error] || 'Unknown payment error'
            Rails.logger.error "Unknown payment service response: #{payment_result}"
            raise Tasker::RetryableError, "Payment service returned unknown status: #{error_message}"
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
