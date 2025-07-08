# frozen_string_literal: true

require_relative '../../../../support/mock_services/payment_gateway'

module BlogExamples
  module Post04
    module StepHandlers
      class ValidatePaymentEligibilityHandler < Tasker::StepHandler::Base
        # Connection method for test mocking compatibility
        def connection
          @connection ||= MockPaymentGateway
        end

        def process(task, _sequence, _step)
          # Extract and validate inputs using our gold standard pattern
          inputs = extract_and_validate_inputs(task.context)

          # Use connection (allows for mocking in tests)
          validation_result = connection.validate_payment_eligibility(inputs)

          # Validate the response indicates eligibility
          ensure_payment_eligible!(validation_result)

          # Return validation result for process_results method
          validation_result
        end

        def process_results(step, validation_result, _initial_results)
          # Safe result processing - set step results directly
          step.results = {
            payment_validated: true,
            payment_id: step.inputs['payment_id'],
            original_amount: validation_result[:original_amount],
            refund_amount: step.inputs['refund_amount'],
            payment_method: validation_result[:payment_method],
            gateway_provider: validation_result[:gateway_provider],
            eligibility_status: validation_result[:status],
            validation_timestamp: Time.current.iso8601,
            namespace: 'payments'
          }
        rescue StandardError => e
          # If result processing fails, don't retry the API call
          raise Tasker::PermanentError,
                "Failed to process validation results: #{e.message}"
        end

        private

        def extract_and_validate_inputs(context)
          # Normalize context to symbols early
          normalized_context = context.deep_symbolize_keys

          # Validate required fields
          required_fields = %i[payment_id refund_amount]
          missing_fields = required_fields.select { |field| normalized_context[field].blank? }

          if missing_fields.any?
            raise Tasker::PermanentError,
                  "Missing required fields for payment validation: #{missing_fields.join(', ')}"
          end

          # Validate refund amount is positive
          refund_amount = normalized_context[:refund_amount]
          if refund_amount <= 0
            raise Tasker::PermanentError,
                  "Refund amount must be positive, got: #{refund_amount}"
          end

          # Validate payment ID format (basic validation)
          payment_id = normalized_context[:payment_id]
          unless payment_id.match?(/^pay_[a-zA-Z0-9]+$/)
            raise Tasker::PermanentError,
                  "Invalid payment ID format: #{payment_id}"
          end

          {
            payment_id: payment_id,
            refund_amount: refund_amount,
            refund_reason: normalized_context[:refund_reason],
            partial_refund: normalized_context[:partial_refund] || false
          }
        end

        def ensure_payment_eligible!(validation_result)
          status = validation_result[:status]

          case status
          when 'eligible'
            # Payment is eligible for refund
            nil
          when 'ineligible'
            # Permanent error - payment cannot be refunded
            raise Tasker::PermanentError,
                  "Payment is not eligible for refund: #{validation_result[:reason]}"
          when 'processing', 'pending'
            # Temporary state - payment is still processing
            raise Tasker::RetryableError,
                  'Payment is still processing, cannot refund yet'
          when 'insufficient_funds'
            # Permanent error - not enough funds to refund
            raise Tasker::PermanentError,
                  'Insufficient funds available for refund'
          else
            # Unknown status - treat as temporary issue
            raise Tasker::RetryableError,
                  "Unknown payment eligibility status: #{status}"
          end
        end
      end
    end
  end
end