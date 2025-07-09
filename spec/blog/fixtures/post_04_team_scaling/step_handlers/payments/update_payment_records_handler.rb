# frozen_string_literal: true

module BlogExamples
  module Post04
    module StepHandlers
      class UpdatePaymentRecordsHandler < Tasker::StepHandler::Base
        def process(task, sequence, step)
          # Extract and validate inputs using our gold standard pattern
          inputs = extract_and_validate_inputs(task.context, step, sequence)

          # Mock call to internal payment records service for blog examples
          {
            payment_id: inputs[:payment_id],
            refund_id: inputs[:refund_id],
            refund_amount: inputs[:refund_amount],
            refund_status: 'completed',
            updated_by: 'automated_workflow',
            namespace: 'payments'
          }

          # Mock internal service call - in reality this would update database records
          update_result = {
            payment_record_updated: true,
            payment_id: inputs[:payment_id],
            refund_id: inputs[:refund_id],
            previous_status: 'active',
            new_status: 'partially_refunded',
            audit_trail_id: "audit_#{SecureRandom.hex(8)}",
            updated_at: Time.current.iso8601
          }

          # Validate the update was successful
          ensure_records_updated!(update_result)
          update_result
        end

        def process_results(step, update_result, _initial_results)
          # Safe result processing - format the payment record update results
          step.results = {
            records_updated: true,
            payment_id: update_result[:payment_id],
            refund_id: update_result[:refund_id],
            payment_status: update_result[:new_status],
            audit_trail_id: update_result[:audit_trail_id],
            updated_timestamp: update_result[:updated_at],
            namespace: 'payments'
          }
        rescue StandardError => e
          # If result processing fails, don't retry the API call
          raise Tasker::PermanentError,
                "Failed to process payment record update results: #{e.message}"
        end

        private

        def extract_and_validate_inputs(context, _step, sequence)
          # Normalize context to symbols early
          normalized_context = context.deep_symbolize_keys

          # Get refund results from previous step
          refund_step = sequence.find_step_by_name('process_gateway_refund')
          refund_results = refund_step&.results&.deep_symbolize_keys

          unless refund_results&.dig(:refund_processed)
            raise Tasker::PermanentError,
                  'Gateway refund must complete before updating payment records'
          end

          # Validate required fields
          required_fields = %i[payment_id]
          missing_fields = required_fields.select { |field| normalized_context[field].blank? }

          if missing_fields.any?
            raise Tasker::PermanentError,
                  "Missing required fields for payment record update: #{missing_fields.join(', ')}"
          end

          {
            payment_id: normalized_context[:payment_id],
            refund_id: refund_results[:refund_id],
            refund_amount: refund_results[:refund_amount],
            gateway_provider: refund_results[:gateway_provider]
          }
        end

        def ensure_records_updated!(update_result)
          unless update_result[:payment_record_updated]
            raise Tasker::PermanentError,
                  'Payment record update failed'
          end

          return if update_result[:audit_trail_id]

          raise Tasker::PermanentError,
                'Payment record updated but audit trail not created'
        end
      end
    end
  end
end
