# frozen_string_literal: true

require_relative 'base_mock_service'

# Mock Manager Approval System
# Simulates manager approval workflow for Post 04 team scaling examples
class MockManagerApprovalSystem < BaseMockService
  # Standard approval system errors
  class ServiceError < StandardError
    attr_reader :error_code

    def initialize(message, error_code: nil)
      super(message)
      @error_code = error_code
    end
  end

  # Request manager approval
  # @param inputs [Hash] Approval request inputs
  # @return [Hash] Approval result
  def self.request_approval(inputs)
    instance = new
    instance.request_approval_call(inputs)
  end

  # Instance method for requesting approval
  def request_approval_call(inputs)
    log_call(:request_approval, inputs)

    # If no approval required, return nil (auto-approve)
    return nil unless inputs[:requires_approval]

    default_response = {
      approval_id: "APPR-#{SecureRandom.hex(4).upcase}",
      status: 'approved',
      approver_id: 'MGR-001',
      approver_name: 'Jane Manager',
      notes: 'Approved based on policy compliance and customer tier',
      approved_at: generate_timestamp,
      processing_time_seconds: 120
    }

    handle_response(:request_approval, default_response)
  end
end
