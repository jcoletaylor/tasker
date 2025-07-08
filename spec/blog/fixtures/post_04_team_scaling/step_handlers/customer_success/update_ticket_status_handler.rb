# frozen_string_literal: true

require_relative '../../../../support/mock_services/customer_service_system'

module BlogExamples
  module Post04
    module StepHandlers
      class UpdateTicketStatusHandler < Tasker::StepHandler::Base
        def process(task, sequence, step)
          # Extract and validate inputs using our gold standard pattern
          inputs = extract_and_validate_inputs(task.context, step, sequence)

          # Mock call to customer service system for blog examples
          begin
            service_response = MockCustomerServiceSystem.update_ticket_status(
              ticket_id: inputs[:ticket_id],
              status: inputs[:status],
              resolution_data: inputs[:resolution_data],
              internal_notes: inputs[:internal_notes],
              customer_message: inputs[:customer_message]
            )

            ensure_ticket_updated!(service_response)
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
                    'Ticket not found in customer service system'
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
          # Safe result processing - format the ticket update results
          step.results = {
            ticket_updated: true,
            ticket_id: service_response[:ticket_id],
            ticket_status: service_response[:status],
            refund_status: service_response[:refund_status],
            customer_notified: service_response[:customer_notified],
            resolution_notes: service_response[:resolution_notes],
            updated_timestamp: Time.current.iso8601
          }
        rescue StandardError => e
          # If result processing fails, don't retry the API call
          raise Tasker::PermanentError,
                "Failed to process ticket update results: #{e.message}"
        end

        private

        def extract_and_validate_inputs(context, step, sequence)
          # Normalize all hash keys to symbols immediately
          normalized_context = context.deep_symbolize_keys

          # Get workflow execution results from previous step
          workflow_step = sequence.find_step_by_name('execute_refund_workflow')
          workflow_results = workflow_step&.results&.deep_symbolize_keys

          unless workflow_results&.dig(:task_delegated)
            raise Tasker::PermanentError,
                  'Refund workflow execution must complete before updating ticket'
          end

          # Validate required ticket ID
          ticket_id = normalized_context[:ticket_id]
          unless ticket_id
            raise Tasker::PermanentError,
                  'Ticket ID is required for status update'
          end

          {
            ticket_id: ticket_id,
            status: 'resolved',
            resolution_data: {
              resolution_type: 'automated_refund',
              delegated_task_id: workflow_results[:delegated_task_id],
              correlation_id: workflow_results[:correlation_id],
              processed_via: 'payments_team_workflow'
            },
            internal_notes: build_internal_notes(step, sequence),
            customer_message: build_customer_message(workflow_results)
          }
        end

        def build_internal_notes(step, sequence)
          # Build comprehensive internal notes for the ticket
          approval_step = sequence.find_step_by_name('get_manager_approval')
          approval_results = approval_step&.results&.deep_symbolize_keys

          policy_step = sequence.find_step_by_name('check_refund_policy')
          policy_results = policy_step&.results&.deep_symbolize_keys

          notes = []
          notes << "Refund processed via automated workflow"
          notes << "Policy compliance: #{policy_results[:policy_version]}" if policy_results
          notes << "Approval method: #{approval_results[:approval_method]}" if approval_results
          notes << "Cross-team coordination: customer_success → payments"

          notes.join('; ')
        end

        def build_customer_message(workflow_results)
          # Build customer-facing message about the refund
          task_id = workflow_results[:delegated_task_id]

          "Your refund request has been processed and sent to our payments team. " \
          "Task ID: #{task_id}. Please allow 3-5 business days for the refund to appear in your account."
        end

        def ensure_ticket_updated!(service_response)
          # Check if the ticket was updated successfully
          case service_response[:status]
          when 'resolved', 'closed'
            # Ticket was successfully updated
            nil
          when 'open', 'in_progress'
            # Unexpected - ticket should be resolved after refund
            raise Tasker::RetryableError,
                  'Ticket update incomplete, current status still pending'
          when 'error'
            # Permanent error - ticket update failed
            raise Tasker::PermanentError,
                  "Ticket update failed: #{service_response[:error_message]}"
          else
            # Unknown status - treat as temporary issue
            raise Tasker::RetryableError,
                  "Unknown ticket update status: #{service_response[:status]}"
          end
        end
      end
    end
  end
end