# frozen_string_literal: true

require_relative 'base_mock_service'

# Mock Customer Service System
# Simulates customer service platform for Post 04 team scaling examples
class MockCustomerServiceSystem < BaseMockService
  # Standard customer service errors
  class ServiceError < StandardError
    attr_reader :error_code

    def initialize(message, error_code: nil)
      super(message)
      @error_code = error_code
    end
  end
  # Validate refund request
  # @param inputs [Hash] Request inputs with ticket_id, customer_id, etc.
  # @return [Hash] Validation result
  def self.validate_refund_request(inputs)
    instance = new
    instance.validate_refund_request_call(inputs)
  end

  # Instance method for validating refund request
  def validate_refund_request_call(inputs)
    log_call(:validate_refund_request, inputs)

    # Check for invalid ticket IDs to simulate error conditions
    if inputs[:ticket_id] == 'INVALID-TICKET'
      raise ServiceError.new('Ticket not found', error_code: 'TICKET_NOT_FOUND')
    end

    default_response = {
      ticket_id: inputs[:ticket_id],
      customer_id: inputs[:customer_id],
      status: 'open',
      customer_tier: 'standard',
      purchase_date: '2024-01-15',
      refund_eligible: true,
      validation_timestamp: generate_timestamp
    }

    handle_response(:validate_refund_request, default_response)
  end

  # Get ticket details
  # @param ticket_id [String] Ticket ID
  # @return [Hash] Ticket details
  def self.get_ticket(ticket_id)
    instance = new
    instance.get_ticket_call(ticket_id)
  end

  # Instance method for getting ticket details
  def get_ticket_call(ticket_id)
    log_call(:get_ticket, { ticket_id: ticket_id })

    default_response = {
      ticket_id: ticket_id,
      status: 'open',
      customer_id: 'CUST-54321',
      subject: 'Product refund request',
      description: 'Customer requesting refund for defective product',
      created_at: generate_timestamp,
      updated_at: generate_timestamp
    }

    handle_response(:get_ticket, default_response)
  end

  # Update ticket status
  # @param ticket_id [String] Ticket ID
  # @param status [String] New status
  # @param notes [String] Update notes
  # @return [Hash] Update result
  def self.update_ticket_status(ticket_id:, status:, notes: nil)
    instance = new
    instance.update_ticket_status_call(ticket_id: ticket_id, status: status, notes: notes)
  end

  # Instance method for updating ticket status
  def update_ticket_status_call(ticket_id:, status:, notes: nil)
    log_call(:update_ticket_status, {
               ticket_id: ticket_id,
               status: status,
               notes: notes
             })

    default_response = {
      ticket_id: ticket_id,
      status: status,
      updated_at: generate_timestamp,
      notes: notes,
      success: true
    }

    handle_response(:update_ticket_status, default_response)
  end
end
