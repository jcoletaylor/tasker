# frozen_string_literal: true

require_relative 'base_mock_service'

# Mock Refund Policy Service
# Simulates policy evaluation for Post 04 team scaling examples
class MockRefundPolicyService < BaseMockService
  # Standard policy service errors
  class ServiceError < StandardError
    attr_reader :error_code

    def initialize(message, error_code: nil)
      super(message)
      @error_code = error_code
    end
  end

  # Evaluate refund policy
  # @param inputs [Hash] Policy evaluation inputs
  # @return [Hash] Policy evaluation result
  def self.evaluate_policy(inputs)
    instance = new
    instance.evaluate_policy_call(inputs)
  end

  # Instance method for evaluating policy
  def evaluate_policy_call(inputs)
    log_call(:evaluate_policy, inputs)

    default_response = {
      policy_version: '2.1.0',
      result: 'approved',
      requires_approval: determine_approval_requirement(inputs),
      max_refund_amount: calculate_max_refund(inputs),
      notes: 'Policy evaluation completed successfully',
      evaluation_timestamp: generate_timestamp
    }

    handle_response(:evaluate_policy, default_response)
  end

  private

  def determine_approval_requirement(inputs)
    # Business logic: require approval for amounts over $100
    (inputs[:refund_amount] || 0) > 10_000 # amounts in cents
  end

  def calculate_max_refund(inputs)
    # Business logic: max refund based on customer tier
    case inputs[:customer_tier]
    when 'premium'
      50_000 # $500 in cents
    when 'standard'
      20_000 # $200 in cents
    else
      10_000 # $100 in cents
    end
  end
end
