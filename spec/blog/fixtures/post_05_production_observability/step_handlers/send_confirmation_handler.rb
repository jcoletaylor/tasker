# frozen_string_literal: true

module BlogExamples
  module Post05
    module StepHandlers
      class SendConfirmationHandler < Tasker::StepHandler::Base
        def process(task, sequence, _step)
          # Get order results
          order_step = sequence.find_step_by_name('create_order')
          order_results = order_step&.results&.deep_symbolize_keys
          
          unless order_results&.dig(:order_created)
            raise Tasker::PermanentError, "Order must be created before sending confirmation"
          end
          
          customer_email = task.context['customer_email']
          unless customer_email
            raise Tasker::PermanentError, "Customer email required for confirmation"
          end
          
          # Simulate email sending
          # Disabled for testing to avoid randomness
          # sleep(rand(0.5..1.5))
          
          # Simulate occasional email service issues
          # Disabled for testing to avoid randomness
          # if rand > 0.97
          #   raise Tasker::RetryableError, "Email service temporarily unavailable"
          # end
          
          {
            confirmation_sent: true,
            email_id: "email_#{SecureRandom.hex(8)}",
            sent_to: customer_email,
            order_id: order_results[:order_id],
            template: 'order_confirmation',
            sent_at: Time.current.iso8601
          }
        end

        def process_results(step, confirmation_results, _initial_results)
          step.results = confirmation_results
        rescue StandardError => e
          raise Tasker::PermanentError,
                "Failed to process confirmation results: #{e.message}"
        end
      end
    end
  end
end