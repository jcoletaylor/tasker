# Payment Simulator for demo purposes
# Simulates various payment gateway scenarios including failures
class PaymentSimulator
  PaymentResult = Struct.new(:status, :id, :amount, :currency, :payment_method_type, :transaction_id, :error)
  
  class << self
    def charge(amount:, payment_method:)
      # Simulate different payment scenarios based on payment method token
      case payment_method
      when /^test_success_/
        success_result(amount, payment_method)
      when /^test_insufficient_/
        insufficient_funds_result
      when /^test_invalid_/
        invalid_card_result
      when /^test_timeout_/
        timeout_result
      when /^test_rate_limit_/
        rate_limit_result
      when /^test_temp_fail_/
        temporary_failure_result
      else
        # Default to success for other tokens (production-like behavior)
        if rand < 0.95  # 95% success rate
          success_result(amount, payment_method)
        else
          random_failure_result
        end
      end
    end
    
    private
    
    def success_result(amount, payment_method)
      PaymentResult.new(
        :success,
        "pi_#{SecureRandom.hex(12)}",
        amount,
        'USD',
        payment_method_type(payment_method),
        "txn_#{SecureRandom.hex(8)}",
        nil
      )
    end
    
    def insufficient_funds_result
      PaymentResult.new(
        :insufficient_funds,
        nil,
        nil,
        nil,
        nil,
        nil,
        "Your card was declined. Your card's limit was exceeded."
      )
    end
    
    def invalid_card_result
      PaymentResult.new(
        :invalid_card,
        nil,
        nil,
        nil,
        nil,
        nil,
        "Your card number is incorrect."
      )
    end
    
    def timeout_result
      PaymentResult.new(
        :gateway_timeout,
        nil,
        nil,
        nil,
        nil,
        nil,
        "Payment gateway timed out after 30 seconds"
      )
    end
    
    def rate_limit_result
      PaymentResult.new(
        :rate_limited,
        nil,
        nil,
        nil,
        nil,
        nil,
        "Too many requests. Please try again in a moment."
      )
    end
    
    def temporary_failure_result
      PaymentResult.new(
        :temporary_failure,
        nil,
        nil,
        nil,
        nil,
        nil,
        "Temporary payment processing error. Please try again."
      )
    end
    
    def random_failure_result
      failures = [
        :gateway_timeout,
        :rate_limited,
        :temporary_failure
      ]
      
      failure_type = failures.sample
      send("#{failure_type}_result")
    end
    
    def payment_method_type(payment_method)
      case payment_method
      when /visa/
        'visa'
      when /mastercard/
        'mastercard'
      when /amex/
        'american_express'
      else
        'card'
      end
    end
  end
end

# Demo usage:
#
# # Successful payment
# result = PaymentSimulator.charge(
#   amount: 49.99,
#   payment_method: 'test_success_visa_4242424242424242'
# )
# puts result.status  # => :success
# puts result.id      # => "pi_abc123def456"
#
# # Failed payment
# result = PaymentSimulator.charge(
#   amount: 49.99,
#   payment_method: 'test_insufficient_funds'
# )
# puts result.status  # => :insufficient_funds
# puts result.error   # => "Your card was declined. Your card's limit was exceeded."
