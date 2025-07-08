# frozen_string_literal: true

module BlogExamples
  module Post05
    module StepHandlers
      class ProcessPaymentHandler < Tasker::StepHandler::Base
        def process(task, sequence, _step)
          # Get cart validation results
          cart_step = sequence.find_step_by_name('validate_cart')
          cart_results = cart_step&.results&.deep_symbolize_keys

          raise Tasker::PermanentError, 'Cart must be validated before payment' unless cart_results&.dig(:validated)

          # Simulate payment processing with variable timing
          # This helps demonstrate performance monitoring
          payment_method = task.context['payment_method'] || 'credit_card'
          amount = cart_results[:cart_total]

          # Simulate occasional slow payments for monitoring
          # Disabled for testing to avoid randomness
          # if rand > 0.9
          #   sleep(rand(3..6)) # Simulate slow payment gateway
          # else
          #   sleep(rand(0.5..2.0))
          # end

          # Simulate occasional failures for error monitoring
          # Disabled for testing to avoid randomness
          # if rand > 0.95
          #   raise Tasker::RetryableError, "Payment gateway timeout"
          # end

          # Return payment results
          {
            payment_successful: true,
            payment_id: "pay_#{SecureRandom.hex(8)}",
            amount: amount,
            payment_method: payment_method,
            processed_at: Time.current.iso8601
          }
        end

        def process_results(step, payment_results, _initial_results)
          step.results = payment_results
        rescue StandardError => e
          raise Tasker::PermanentError,
                "Failed to process payment results: #{e.message}"
        end
      end
    end
  end
end
