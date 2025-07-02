module Ecommerce
  module StepHandlers
    class ProcessPaymentHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        payment_info = task.context['payment_info']
        cart_validation = step_results(sequence, 'validate_cart')

        amount_to_charge = cart_validation['total']

        Rails.logger.info "Processing payment", {
          task_id: task.task_id,
          amount: amount_to_charge
        }

        # Validate payment amount matches cart total
        if payment_info['amount'] != amount_to_charge
          Rails.logger.error "Payment amount mismatch. Expected: #{amount_to_charge}, Provided: #{payment_info['amount']}"
          raise StandardError, "Payment amount mismatch. Expected: #{amount_to_charge}, Provided: #{payment_info['amount']}"
        end

        # Process payment using payment simulator
        result = PaymentSimulator.charge(
          amount: amount_to_charge,
          payment_method: payment_info['token']
        )

        case result.status
        when :success
          Rails.logger.info "Payment processed successfully", {
            task_id: task.task_id,
            payment_id: result.id,
            amount_charged: result.amount
          }

          {
            payment_id: result.id,
            amount_charged: result.amount,
            currency: result.currency,
            payment_method_type: result.payment_method_type,
            transaction_id: result.transaction_id,
            processed_at: Time.current.iso8601
          }
        when :insufficient_funds
          Rails.logger.error "Payment declined: Insufficient funds"
          raise StandardError, "Payment declined: Insufficient funds"
        when :invalid_card
          Rails.logger.error "Payment declined: Invalid card"
          raise StandardError, "Payment declined: Invalid card"
        when :gateway_timeout
          # Temporary failure - will retry based on step configuration
          Rails.logger.warn "Payment gateway timeout - will retry"
          raise StandardError, "Payment gateway timeout - will retry"
        when :rate_limited
          # Temporary failure - will retry based on step configuration
          Rails.logger.warn "Payment gateway rate limited - will retry"
          raise StandardError, "Payment gateway rate limited - will retry"
        when :temporary_failure
          # Temporary failure - will retry based on step configuration
          Rails.logger.warn "Temporary payment failure: #{result.error}"
          raise StandardError, "Temporary payment failure: #{result.error}"
        else
          Rails.logger.error "Unknown payment error: #{result.error}"
          raise StandardError, "Unknown payment error: #{result.error}"
        end
      end

      private

      def step_results(sequence, step_name)
        step = sequence.steps.find { |s| s.name == step_name }
        step&.results || {}
      end
    end
  end
end
