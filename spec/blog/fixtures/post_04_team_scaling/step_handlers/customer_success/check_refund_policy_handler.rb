# frozen_string_literal: true

require_relative '../../../../support/mock_services/refund_policy_service'

module BlogExamples
  module Post04
    module StepHandlers
      class CheckRefundPolicyHandler < Tasker::StepHandler::Base
        def process(task, sequence, step)
          # Extract and validate inputs using our gold standard pattern
          inputs = extract_and_validate_inputs(task.context, sequence, step)

          # Make API call to policy engine using mock service
          response = MockRefundPolicyService.evaluate_policy(inputs)

          # Process the response and classify errors
          ensure_policy_compliant!(response)
          response
        end

        def process_results(step, service_response, _initial_results)
          # Safe result processing - format the policy check results
          step.results = {
            policy_compliant: true,
            policy_version: service_response[:policy_version],
            evaluation_result: service_response[:result],
            requires_approval: service_response[:requires_approval],
            max_refund_amount: service_response[:max_refund_amount],
            policy_notes: service_response[:notes],
            evaluation_timestamp: Time.current.iso8601
          }
        rescue StandardError => e
          # If result processing fails, don't retry the API call
          raise Tasker::PermanentError,
                "Failed to process policy evaluation results: #{e.message}"
        end

        private

        def extract_and_validate_inputs(context, sequence, step)
          # Normalize all hash keys to symbols immediately
          normalized_context = context.deep_symbolize_keys

          # Get validation results from previous step
          validation_step = sequence.find_step_by_name('validate_refund_request')
          validation_results = validation_step&.results&.deep_symbolize_keys

          unless validation_results&.dig(:request_validated)
            raise Tasker::PermanentError,
                  'Refund request validation must complete before policy check'
          end

          {
            ticket_id: normalized_context[:ticket_id],
            customer_id: validation_results[:customer_id],
            customer_tier: validation_results[:customer_tier],
            refund_amount: normalized_context[:refund_amount],
            refund_reason: normalized_context[:refund_reason],
            original_purchase_date: validation_results[:original_purchase_date]
          }
        end

        def ensure_policy_compliant!(service_response)
          # Check if the refund request complies with policies
          case service_response[:result]
          when 'approved', 'conditional_approval'
            # Policy allows the refund
            nil
          when 'denied'
            # Permanent error - policy violation
            raise Tasker::PermanentError,
                  "Refund request violates policy: #{service_response[:reason]}"
          when 'requires_review'
            # This might be retryable if review process is automated
            raise Tasker::RetryableError,
                  'Refund request requires additional policy review'
          else
            # Unknown result - treat as temporary issue
            raise Tasker::RetryableError,
                  "Unknown policy evaluation result: #{service_response[:result]}"
          end
        end
      end
    end
  end
end