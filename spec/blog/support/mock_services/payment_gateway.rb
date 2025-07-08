# frozen_string_literal: true

require_relative 'base_mock_service'

# Mock Payment Gateway
# Simulates payment gateway operations for Post 04 team scaling examples
class MockPaymentGateway < BaseMockService
  # Standard payment gateway errors
  class ServiceError < StandardError
    attr_reader :error_code

    def initialize(message, error_code: nil)
      super(message)
      @error_code = error_code
    end
  end

  # Validate payment eligibility for refund
  # @param inputs [Hash] Payment validation inputs
  # @return [Hash] Validation result
  def self.validate_payment_eligibility(inputs)
    instance = new
    instance.validate_payment_eligibility_call(inputs)
  end

  # Process gateway refund
  # @param inputs [Hash] Refund processing inputs
  # @return [Hash] Refund result
  def self.process_refund(inputs)
    instance = new
    instance.process_refund_call(inputs)
  end

  # Instance method for validating payment eligibility
  def validate_payment_eligibility_call(inputs)
    log_call(:validate_payment_eligibility, inputs)

    default_response = {
      status: 'eligible',
      payment_id: inputs[:payment_id],
      original_amount: 15000,
      payment_method: 'credit_card',
      gateway_provider: 'stripe',
      transaction_date: '2024-01-15T10:30:00Z',
      refund_window_expires: '2024-02-15T10:30:00Z'
    }

    handle_response(:validate_payment_eligibility, default_response)
  end

  # Instance method for processing refund
  def process_refund_call(inputs)
    log_call(:process_refund, inputs)

    default_response = {
      refund_id: "ref_#{SecureRandom.hex(8)}",
      status: 'completed',
      amount: inputs[:refund_amount],
      currency: 'usd',
      gateway_transaction_id: "gtx_#{SecureRandom.hex(6)}",
      processed_at: generate_timestamp,
      estimated_arrival: (Time.current + 3.days).iso8601
    }

    handle_response(:process_refund, default_response)
  end
end
