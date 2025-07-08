# frozen_string_literal: true

require_relative '../../../../support/mock_services/customer_service_system'

module BlogExamples
  module Post04
    module StepHandlers
      class ValidateRefundRequestHandler < Tasker::StepHandler::Base
        def process(task, _sequence, _step)
          # Extract and validate inputs using our gold standard pattern
          inputs = extract_and_validate_inputs(task.context)

          # Make API call to customer service platform using mock service
          begin
            service_response = MockCustomerServiceSystem.validate_refund_request(inputs)
            service_response = service_response.deep_symbolize_keys
            ensure_request_valid!(service_response)
            service_response
          rescue MockCustomerServiceSystem::ServiceError => e
            # Handle customer service system errors
            case e.message
            when /connection failed/i, /timeout/i
              raise Tasker::RetryableError,
                    'Customer service platform connection failed, will retry'
            when /authentication/i, /authorization/i
              raise Tasker::PermanentError,
                    'Customer service platform authentication failed'
            when /not found/i
              raise Tasker::PermanentError,
                    'Ticket or customer not found in customer service system'
            when /unavailable/i
              raise Tasker::RetryableError,
                    'Customer service platform unavailable, will retry'
            else
              raise Tasker::RetryableError,
                    "Customer service system error: #{e.message}"
            end
          end
        end

        def process_results(step, service_response, _initial_results)
          # Safe result processing - format the validation results
          step.results = {
            request_validated: true,
            ticket_id: service_response[:ticket_id],
            customer_id: service_response[:customer_id],
            ticket_status: service_response[:status],
            customer_tier: service_response[:customer_tier],
            original_purchase_date: service_response[:purchase_date],
            payment_id: service_response[:payment_id],
            validation_timestamp: Time.current.iso8601
          }
        rescue StandardError => e
          # If result processing fails, don't retry the API call
          raise Tasker::PermanentError,
                "Failed to process validation results: #{e.message}"
        end

        private

        def extract_and_validate_inputs(context)
          # Normalize all hash keys to symbols immediately
          normalized_context = context.deep_symbolize_keys

          # Validate required fields
          required_fields = %i[ticket_id customer_id refund_amount]
          missing_fields = required_fields.select { |field| normalized_context[field].blank? }

          if missing_fields.any?
            raise Tasker::PermanentError,
                  "Missing required fields for refund validation: #{missing_fields.join(', ')}"
          end

          {
            ticket_id: normalized_context[:ticket_id],
            customer_id: normalized_context[:customer_id],
            refund_amount: normalized_context[:refund_amount],
            refund_reason: normalized_context[:refund_reason]
          }
        end

        def ensure_request_valid!(service_response)
          # Check if the ticket is in a valid state for refund processing
          case service_response[:status]
          when 'open', 'in_progress'
            # Ticket is active and can be processed
            nil
          when 'closed'
            # Permanent error - can't process refunds for closed tickets
            raise Tasker::PermanentError,
                  'Cannot process refund for closed ticket'
          when 'cancelled'
            # Permanent error - ticket was cancelled
            raise Tasker::PermanentError,
                  'Cannot process refund for cancelled ticket'
          when 'duplicate'
            # Permanent error - duplicate ticket
            raise Tasker::PermanentError,
                  'Cannot process refund for duplicate ticket'
          else
            # Unknown status - treat as temporary issue
            raise Tasker::RetryableError,
                  "Unknown ticket status: #{service_response[:status]}"
          end
        end
      end
    end
  end
end
