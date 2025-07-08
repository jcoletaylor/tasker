# frozen_string_literal: true

require_relative '../../../../support/mock_services/payment_gateway'

module BlogExamples
  module Post04
    module StepHandlers
      class ProcessGatewayRefundHandler < Tasker::StepHandler::Base
        def process(task, sequence, step)
          # Extract and validate inputs using our gold standard pattern
          inputs = extract_and_validate_inputs(task.context, step, sequence)

          # Use mock service instead of real API call for blog examples
          refund_data = {
            payment_id: inputs[:payment_id],
            refund_amount: inputs[:refund_amount],
            refund_reason: inputs[:refund_reason],
            partial_refund: inputs[:partial_refund],
            namespace: 'payments'
          }

          begin
            refund_result = MockPaymentGateway.process_refund(refund_data)

            # Validate the refund was successful
            ensure_refund_successful!(refund_result)

            # Return refund result for process_results method
            refund_result
          rescue MockPaymentGateway::ServiceError => e
            # Handle payment gateway service errors
            case e.message
            when /connection failed/i
              raise Tasker::PermanentError,
                    "Payment gateway connection failed: #{e.message}"
            when /unavailable/i, /timeout/i
              raise Tasker::RetryableError,
                    "Payment gateway service unavailable: #{e.message}"
            when /authentication/i, /authorization/i
              raise Tasker::PermanentError,
                    "Payment gateway authentication failed: #{e.message}"
            else
              # Default to retryable for unknown gateway errors
              raise Tasker::RetryableError,
                    "Payment gateway error: #{e.message}"
            end
          end
        end

        def process_results(step, refund_result, _initial_results)
          # Safe result processing - format the refund results
          step.results = {
            refund_processed: true,
            refund_id: refund_result[:refund_id],
            payment_id: step.inputs['payment_id'],
            refund_amount: step.inputs['refund_amount'],
            gateway_provider: refund_result[:gateway_provider],
            gateway_refund_id: refund_result[:gateway_refund_id],
            refund_status: refund_result[:status],
            processing_time_seconds: refund_result[:processing_time_seconds],
            processed_at: refund_result[:processed_at],
            namespace: 'payments'
          }
        rescue StandardError => e
          # If result processing fails, don't retry the API call
          raise Tasker::PermanentError,
                "Failed to process refund results: #{e.message}"
        end

        private

        def extract_and_validate_inputs(context, _step, sequence)
          # Normalize context to symbols early
          normalized_context = context.deep_symbolize_keys

          # Get validation results from previous step
          validation_step = sequence.find_step_by_name('validate_payment_eligibility')
          validation_results = validation_step&.results&.deep_symbolize_keys || {}

          # Validate required fields from context
          required_fields = %i[payment_id refund_amount]
          missing_fields = required_fields.select { |field| normalized_context[field].blank? }

          if missing_fields.any?
            raise Tasker::PermanentError,
                  "Missing required fields for gateway refund: #{missing_fields.join(', ')}"
          end

          # Validate we have validation results from previous step
          unless validation_results[:payment_validated]
            raise Tasker::PermanentError,
                  'Payment validation must be completed before processing refund'
          end

          # Validate refund amount matches validation
          if normalized_context[:refund_amount] != validation_results[:refund_amount]
            raise Tasker::PermanentError,
                  "Refund amount mismatch: context=#{normalized_context[:refund_amount]}, validated=#{validation_results[:refund_amount]}"
          end

          {
            payment_id: normalized_context[:payment_id],
            refund_amount: normalized_context[:refund_amount],
            refund_reason: normalized_context[:refund_reason] || 'customer_request',
            partial_refund: normalized_context[:partial_refund] || false,
            gateway_provider: validation_results[:gateway_provider],
            original_amount: validation_results[:original_amount]
          }
        end

        def ensure_refund_successful!(refund_result)
          status = refund_result[:status]

          case status
          when 'processed', 'completed'
            # Refund was successful
            nil
          when 'failed'
            # Permanent error - refund failed
            error_code = refund_result[:error_code]
            error_message = refund_result[:error_message]

            case error_code
            when 'insufficient_funds'
              raise Tasker::PermanentError,
                    "Insufficient funds for refund: #{error_message}"
            when 'invalid_payment'
              raise Tasker::PermanentError,
                    "Invalid payment for refund: #{error_message}"
            when 'already_refunded'
              raise Tasker::PermanentError,
                    "Payment already refunded: #{error_message}"
            else
              raise Tasker::PermanentError,
                    "Refund failed: #{error_message}"
            end
          when 'pending'
            # Temporary state - refund is processing
            raise Tasker::RetryableError,
                  'Refund is still processing, will retry'
          when 'rate_limited'
            # Temporary error - too many requests
            raise Tasker::RetryableError,
                  'Gateway rate limited, will retry'
          else
            # Unknown status - treat as temporary issue
            raise Tasker::RetryableError,
                  "Unknown refund status: #{status}"
          end
        end
      end
    end
  end
end
