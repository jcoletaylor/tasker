# frozen_string_literal: true

require_relative '../../../../support/mock_services/manager_approval_system'

module BlogExamples
  module Post04
    module StepHandlers
      class GetManagerApprovalHandler < Tasker::StepHandler::Base
        def process(task, sequence, step)
          # Extract and validate inputs using our gold standard pattern
          inputs = extract_and_validate_inputs(task.context, sequence, step)

          # Skip approval if policy says it's not required
          unless inputs[:requires_approval]
            # Auto-approve - no manager approval needed
            return nil
          end

          # Make API call to manager approval system using mock service
          service_response = MockManagerApprovalSystem.request_approval(inputs)
          ensure_approval_processed!(service_response)
          service_response
        end

        def process_results(step, service_response, _initial_results)
          # Safe result processing - format the approval results
          # Handle auto-approval case (when service_response is nil)
          step.results = if service_response.nil?
                           {
                             approval_obtained: true,
                             approval_method: 'auto_approval',
                             approval_reason: 'policy_exemption',
                             approved_by: 'system',
                             approval_id: "auto_#{SecureRandom.hex(8)}",
                             approval_timestamp: Time.current.iso8601
                           }
                         else
                           {
                             approval_obtained: true,
                             approval_method: 'manager_approval',
                             approved_by: service_response[:approved_by],
                             approval_id: service_response[:approval_id],
                             approval_notes: service_response[:notes],
                             approval_timestamp: service_response[:approved_at]
                           }
                         end
        rescue StandardError => e
          # If result processing fails, don't retry the API call
          raise Tasker::PermanentError,
                "Failed to process approval results: #{e.message}"
        end

        private

        def extract_and_validate_inputs(context, sequence, _step)
          # Normalize all hash keys to symbols immediately
          normalized_context = context.deep_symbolize_keys

          # Get policy results from previous step
          policy_step = sequence.find_step_by_name('check_refund_policy')
          policy_results = policy_step&.results&.deep_symbolize_keys

          unless policy_results&.dig(:policy_compliant)
            raise Tasker::PermanentError,
                  'Policy compliance check must complete before approval request'
          end

          {
            ticket_id: normalized_context[:ticket_id],
            customer_id: normalized_context[:customer_id],
            refund_amount: normalized_context[:refund_amount],
            refund_reason: normalized_context[:refund_reason],
            requires_approval: policy_results[:requires_approval],
            policy_notes: policy_results[:policy_notes],
            agent_notes: normalized_context[:agent_notes]
          }
        end

        def ensure_approval_processed!(service_response)
          # Check if the approval request was processed correctly
          case service_response[:status]
          when 'approved'
            # Manager approved the refund
            nil
          when 'denied'
            # Permanent error - manager denied the refund
            raise Tasker::PermanentError,
                  "Manager denied refund request: #{service_response[:reason]}"
          when 'pending'
            # Temporary state - approval is still pending
            raise Tasker::RetryableError,
                  'Approval request is pending, will check again'
          when 'expired'
            # Permanent error - approval request expired
            raise Tasker::PermanentError,
                  'Approval request expired without response'
          else
            # Unknown status - treat as temporary issue
            raise Tasker::RetryableError,
                  "Unknown approval status: #{service_response[:status]}"
          end
        end
      end
    end
  end
end
