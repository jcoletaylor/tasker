module BlogExamples
  module Post01
    module StepHandlers
      class ProcessPaymentHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        payment_info = task.context['payment_info']
        cart_validation = step_results(sequence, 'validate_cart')

        amount_to_charge = cart_validation['total']

        Rails.logger.info "Processing payment: task_id=#{task.task_id}, amount=#{amount_to_charge}"

        # Validate payment amount matches cart total
        # Convert both amounts to BigDecimal to handle precision correctly
        expected_amount = BigDecimal(amount_to_charge.to_s)
        provided_amount = BigDecimal(payment_info['amount'].to_s)

        if provided_amount != expected_amount
          Rails.logger.error "Payment amount mismatch. Expected: #{expected_amount}, Provided: #{provided_amount}"
          raise StandardError, "Payment amount mismatch. Expected: #{expected_amount}, Provided: #{provided_amount}"
        end

        # Process payment using mock service for blog validation
        result = MockPaymentService.process_payment(
          amount: amount_to_charge,
          method: payment_info['method'] || 'credit_card',
          token: payment_info['token']
        )

        # Handle mock service response (Hash format)
        if result[:status] == 'succeeded' || result['status'] == 'succeeded'
          payment_id = result[:payment_id] || result['payment_id']
          amount_charged = result[:amount_charged] || result['amount_charged']

          Rails.logger.info "Payment processed successfully: task_id=#{task.task_id}, payment_id=#{payment_id}, amount_charged=#{amount_charged}"

          {
            payment_id: payment_id,
            amount_charged: amount_charged,
            currency: result[:currency] || result['currency'] || 'USD',
            payment_method_type: result[:payment_method_type] || result['payment_method_type'] || 'credit_card',
            transaction_id: result[:transaction_id] || result['transaction_id'],
            processed_at: Time.current.iso8601
          }
        else
          # Handle payment failures - in a real implementation, you'd check specific error types
          error_message = result[:error] || result['error'] || 'Payment processing failed'
          Rails.logger.error "Payment failed: #{error_message}"
          raise StandardError, "Payment failed: #{error_message}"
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
end
