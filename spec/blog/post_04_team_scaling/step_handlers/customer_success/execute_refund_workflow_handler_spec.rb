# frozen_string_literal: true

require_relative '../../../support/blog_spec_helper'

RSpec.describe 'BlogExamples::Post04::StepHandlers::ExecuteRefundWorkflowHandler', type: :blog_example do
  let(:handler_class) { BlogExamples::Post04::StepHandlers::ExecuteRefundWorkflowHandler }
  let(:handler_config) { Tasker::StepHandler::Api::Config.new(url: 'http://payments-service.example.com') }
  let(:handler) { handler_class.new(config: handler_config) }

  let(:valid_context) do
    {
      ticket_id: 'TICKET-12345',
      customer_id: 'CUST-67890',
      refund_amount: 7500, # $75.00 in cents
      refund_reason: 'Defective product',
      agent_notes: 'Customer reported product malfunction',
      correlation_id: 'cs-abc123def456'
    }
  end

  let(:mock_task) { double('Task', context: valid_context) }
  let(:mock_step) { double('Step') }
  let(:mock_connection) { double('Connection') }
  let(:mock_response) { double('Response') }
  let(:mock_sequence) { double('Sequence') }
  let(:mock_validation_step) { double('ValidationStep', results: validation_results) }
  let(:mock_approval_step) { double('ApprovalStep', results: approval_results) }

  # Mock previous step results
  let(:validation_results) do
    {
      request_validated: true,
      ticket_id: 'TICKET-12345',
      customer_id: 'CUST-67890',
      payment_id: 'pay_987654321', # This is the key mapping
      customer_tier: 'premium',
      original_purchase_date: '2024-01-15'
    }
  end

  let(:approval_results) do
    {
      approval_obtained: true,
      approval_method: 'manager_approved',
      approval_id: 'APPR-789',
      approver_id: 'MGR-456',
      approval_notes: 'Approved due to product defect'
    }
  end

  before do
    # Load Post 04 blog code
    load_blog_code_safely('post_04_team_scaling')

    # Setup mock connection
    allow(handler).to receive(:connection).and_return(mock_connection)

    # Setup mock step with sequence access
    allow(mock_step).to receive(:sequence).and_return(mock_sequence)
    allow(mock_sequence).to receive(:find_step_by_name)
      .with('validate_refund_request')
      .and_return(mock_validation_step)
    allow(mock_sequence).to receive(:find_step_by_name)
      .with('get_manager_approval')
      .and_return(mock_approval_step)
  end

  describe '#process - Cross-Namespace Coordination' do
    context 'with successful workflow execution' do
      before do
        allow(mock_connection).to receive(:post)
          .with('/tasker/tasks', hash_including(namespace: 'payments'))
          .and_return(mock_response)

        allow(mock_response).to receive_messages(status: 201, body: {
          task_id: 'TASK-PAY-123',
          status: 'created',
          workflow_name: 'process_refund',
          namespace: 'payments',
          correlation_id: 'cs-abc123def456'
        }.to_json)
      end

      it 'successfully executes cross-namespace workflow' do
        result = handler.process(mock_task, mock_sequence, mock_step)
        expect(result).to eq(mock_response)
      end

      it 'makes correct cross-namespace API call' do
        expected_payload = {
          namespace: 'payments',
          workflow_name: 'process_refund',
          workflow_version: '2.1.0',
          context: {
            payment_id: 'pay_987654321', # Mapped from customer service ticket
            refund_amount: 7500,
            refund_reason: 'Defective product',
            initiated_by: 'customer_success',
            approval_id: 'APPR-789',
            ticket_id: 'TICKET-12345',
            correlation_id: 'cs-abc123def456'
          }
        }

        expect(mock_connection).to receive(:post)
          .with('/tasker/tasks', expected_payload)

        handler.process(mock_task, mock_sequence, mock_step)
      end

      it 'generates correlation ID when not provided' do
        context_without_correlation = valid_context.dup
        context_without_correlation.delete(:correlation_id)
        task_without_correlation = double('Task', context: context_without_correlation)

        allow(SecureRandom).to receive(:hex).with(8).and_return('generated123')

        expect(mock_connection).to receive(:post)
          .with('/tasker/tasks', hash_including(
                                   context: hash_including(correlation_id: 'cs-generated123')
                                 ))

        handler.process(task_without_correlation, mock_sequence, mock_step)
      end
    end

    context 'with missing approval' do
      before do
        mock_failed_approval_step = double('FailedApprovalStep', results: { approval_obtained: false })
        allow(mock_sequence).to receive(:find_step_by_name)
          .with('get_manager_approval')
          .and_return(mock_failed_approval_step)
      end

      it 'raises permanent error when approval not obtained' do
        expect { handler.process(mock_task, mock_sequence, mock_step) }
          .to raise_error(Tasker::PermanentError, /Manager approval must be obtained/)
      end
    end

    context 'with missing payment ID' do
      before do
        mock_failed_validation_step = double('FailedValidationStep', results: { request_validated: true }) # Missing payment_id
        allow(mock_sequence).to receive(:find_step_by_name)
          .with('validate_refund_request')
          .and_return(mock_failed_validation_step)
      end

      it 'raises permanent error when payment ID not found' do
        expect { handler.process(mock_task, mock_sequence, mock_step) }
          .to raise_error(Tasker::PermanentError, /Payment ID not found/)
      end
    end

    context 'with API errors' do
      before do
        allow(mock_connection).to receive(:post).and_return(mock_response)
      end

      it 'raises permanent error for 400 status' do
        allow(mock_response).to receive(:status).and_return(400)

        expect { handler.process(mock_task, mock_sequence, mock_step) }
          .to raise_error(Tasker::PermanentError, /Invalid task creation request/)
      end

      it 'raises permanent error for 403 status' do
        allow(mock_response).to receive(:status).and_return(403)

        expect { handler.process(mock_task, mock_sequence, mock_step) }
          .to raise_error(Tasker::PermanentError, /Not authorized to create tasks in payments namespace/)
      end

      it 'raises permanent error for 404 status' do
        allow(mock_response).to receive(:status).and_return(404)

        expect { handler.process(mock_task, mock_sequence, mock_step) }
          .to raise_error(Tasker::PermanentError, /Payments workflow definition not found/)
      end

      it 'raises retryable error for 429 status' do
        allow(mock_response).to receive(:status).and_return(429)

        expect { handler.process(mock_task, mock_sequence, mock_step) }
          .to raise_error(Tasker::RetryableError, /Task creation rate limited/)
      end

      it 'raises retryable error for 500 status' do
        allow(mock_response).to receive(:status).and_return(500)

        expect { handler.process(mock_task, mock_sequence, mock_step) }
          .to raise_error(Tasker::RetryableError, /Tasker system unavailable/)
      end
    end

    context 'with workflow execution failures' do
      before do
        allow(mock_connection).to receive(:post).and_return(mock_response)
        allow(mock_response).to receive(:status).and_return(200)
      end

      it 'raises permanent error for failed task creation' do
        allow(mock_response).to receive(:body).and_return({
          status: 'failed',
          error_message: 'Task creation failed'
        }.to_json)

        expect { handler.process(mock_task, mock_sequence, mock_step) }
          .to raise_error(Tasker::PermanentError, /Task creation failed/)
      end

      it 'raises permanent error for rejected task creation' do
        allow(mock_response).to receive(:body).and_return({
          status: 'rejected',
          rejection_reason: 'Insufficient permissions'
        }.to_json)

        expect { handler.process(mock_task, mock_sequence, mock_step) }
          .to raise_error(Tasker::PermanentError, /Task creation rejected/)
      end

      it 'raises error for missing task_id in created task' do
        allow(mock_response).to receive(:body).and_return({
          status: 'created'
          # Missing task_id
        }.to_json)

        expect { handler.process(mock_task, mock_sequence, mock_step) }
          .to raise_error(Tasker::PermanentError, /Task created but no task_id returned/)
      end
    end
  end

  describe '#process_results - Cross-Team Data Mapping' do
    let(:service_response) do
      {
        task_id: 'TASK-PAY-123',
        status: 'created',
        workflow_name: 'process_refund',
        namespace: 'payments',
        correlation_id: 'cs-abc123def456'
      }
    end

    it 'formats cross-namespace task delegation results' do
      allow(mock_step).to receive(:results=)

      handler.process_results(mock_step, service_response, {})

      expect(mock_step).to have_received(:results=).with(hash_including(
                                                           task_delegated: true,
                                                           target_namespace: 'payments',
                                                           target_workflow: 'process_refund',
                                                           delegated_task_id: 'TASK-PAY-123',
                                                           delegated_task_status: 'created',
                                                           correlation_id: 'cs-abc123def456'
                                                         ))
    end

    it 'handles result processing errors' do
      allow(Time).to receive(:current).and_raise(StandardError, 'Time error')

      expect { handler.process_results(mock_step, service_response, {}) }
        .to raise_error(Tasker::PermanentError, /Failed to process task creation results/)
    end
  end

  describe 'data mapping between teams' do
    it 'correctly maps customer service data to payments context' do
      # This test demonstrates the key Post 04 pattern:
      # How different teams have different data models but can coordinate

      customer_service_context = {
        ticket_id: 'TICKET-999',
        customer_id: 'CUST-888',
        refund_amount: 12_000,
        refund_reason: 'Service issue',
        agent_notes: 'Customer complained about service quality'
      }

      task_with_cs_data = double('Task', context: customer_service_context)

      expected_payments_context = {
        payment_id: 'pay_987654321', # Mapped from validation results
        refund_amount: 12_000,
        refund_reason: 'Service issue',
        initiated_by: 'customer_success',
        approval_id: 'APPR-789',
        ticket_id: 'TICKET-999',
        correlation_id: anything # Generated or passed through
      }

      expect(mock_connection).to receive(:post)
        .with('/tasker/tasks', hash_including(
                                 namespace: 'payments',
                                 workflow_name: 'process_refund',
                                 workflow_version: '2.1.0',
                                 context: hash_including(expected_payments_context)
                               ))
        .and_return(mock_response)

      allow(mock_response).to receive_messages(status: 201, body: {
        task_id: 'TASK-PAY-999',
        status: 'created'
      }.to_json)

      handler.process(task_with_cs_data, mock_sequence, mock_step)
    end
  end

  describe 'correlation ID generation' do
    it 'generates correlation ID with customer success prefix' do
      allow(SecureRandom).to receive(:hex).with(8).and_return('abcd1234')

      correlation_id = handler.send(:generate_correlation_id)
      expect(correlation_id).to eq('cs-abcd1234')
    end
  end
end
