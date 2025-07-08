# frozen_string_literal: true

require_relative '../../../support/blog_spec_helper'

RSpec.describe 'BlogExamples::Post04::StepHandlers::ValidatePaymentEligibilityHandler', type: :blog_example do
  let(:handler_class) { BlogExamples::Post04::StepHandlers::ValidatePaymentEligibilityHandler }
  let(:handler) { handler_class.new }

  let(:valid_context) do
    {
      'payment_id' => 'pay_123456789',
      'refund_amount' => 5000, # $50.00 in cents
      'refund_reason' => 'customer_request',
      'partial_refund' => false,
      'correlation_id' => 'corr_abc123'
    }
  end

  let(:task) do
    create_test_task(
      name: 'process_refund',
      namespace: 'payments',
      context: valid_context
    )
  end

  let(:step) do
    task.workflow_steps.find { |s| s.name == 'validate_payment_eligibility' }
  end

  before do
    # Load Post 04 blog code
    load_blog_code_safely('post_04_team_scaling')

    # Reset the mock payment gateway before each test
    MockPaymentGateway.reset!
  end

  describe '#process' do
    context 'with valid payment eligible for refund' do
      before do
        # Configure the mock to return successful eligibility response
        MockPaymentGateway.stub_response(:validate_payment_eligibility, {
          status: 'eligible',
          payment_id: 'pay_123456789',
          original_amount: 15000,
          payment_method: 'credit_card',
          gateway_provider: 'stripe',
          transaction_date: '2024-01-15T10:30:00Z',
          refund_window_expires: '2024-02-15T10:30:00Z'
        })
      end

      it 'successfully validates payment eligibility' do
        result = handler.process(task, task.workflow_steps, step)
        
        # The handler should return the validation result
        expect(result).to be_a(Hash)
        expect(result[:status]).to eq('eligible')
        expect(result[:payment_id]).to eq('pay_123456789')
      end

      it 'makes correct service call with proper inputs' do
        handler.process(task, task.workflow_steps, step)
        
        # Verify the mock service was called with the right parameters
        calls = MockPaymentGateway.calls_for(:validate_payment_eligibility)
        expect(calls.size).to eq(1)
        
        call_args = calls.first[:args]
        expect(call_args[:payment_id]).to eq('pay_123456789')
        expect(call_args[:refund_amount]).to eq(5000)
        expect(call_args[:refund_reason]).to eq('customer_request')
        expect(call_args[:partial_refund]).to eq(false)
      end

      it 'populates step results correctly' do
        validation_result = handler.process(task, task.workflow_steps, step)
        handler.process_results(step, validation_result, {})
        
        expect(step.results).to include(
          'payment_validated' => true,
          'payment_id' => 'pay_123456789',
          'eligibility_status' => 'eligible',
          'original_amount' => 15000,
          'namespace' => 'payments'
        )
        expect(step.results['validation_timestamp']).to be_present
      end
    end

    context 'with payment ineligible for refund' do
      before do
        MockPaymentGateway.stub_response(:validate_payment_eligibility, {
          status: 'ineligible',
          payment_id: 'pay_123456789',
          reason: 'Payment already fully refunded'
        })
      end

      it 'raises permanent error for ineligible payment' do
        expect { handler.process(task, task.workflow_steps, step) }
          .to raise_error(Tasker::PermanentError, /Payment is not eligible for refund/)
      end
    end

    context 'with payment still processing' do
      before do
        MockPaymentGateway.stub_response(:validate_payment_eligibility, {
          status: 'processing',
          payment_id: 'pay_123456789'
        })
      end

      it 'raises retryable error for processing payment' do
        expect { handler.process(task, task.workflow_steps, step) }
          .to raise_error(Tasker::RetryableError, /Payment is still processing/)
      end
    end

    context 'with insufficient funds' do
      before do
        MockPaymentGateway.stub_response(:validate_payment_eligibility, {
          status: 'insufficient_funds',
          payment_id: 'pay_123456789'
        })
      end

      it 'raises permanent error for insufficient funds' do
        expect { handler.process(task, task.workflow_steps, step) }
          .to raise_error(Tasker::PermanentError, /Insufficient funds available for refund/)
      end
    end

    context 'with missing required fields' do
      let(:invalid_context) { { 'payment_id' => 'pay_123' } } # Missing refund_amount
      let(:invalid_task) do
        create_test_task(
          name: 'process_refund',
          namespace: 'payments',
          context: invalid_context
        )
      end
      let(:invalid_step) do
        invalid_task.workflow_steps.find { |s| s.name == 'validate_payment_eligibility' }
      end

      it 'raises permanent error for missing fields' do
        expect { handler.process(invalid_task, invalid_task.workflow_steps, invalid_step) }
          .to raise_error(Tasker::PermanentError, /Missing required fields/)
      end
    end

    context 'with service errors' do
      it 'handles service exceptions appropriately' do
        # Configure the mock to simulate a service error
        MockPaymentGateway.stub_failure(:validate_payment_eligibility, 
          MockPaymentGateway::ServiceError, 'Service unavailable')

        expect { handler.process(task, task.workflow_steps, step) }
          .to raise_error(MockPaymentGateway::ServiceError, /Service unavailable/)
      end
    end
  end

  describe '#process_results' do
    let(:service_response) do
      {
        status: 'eligible',
        payment_id: 'pay_123456789',
        original_amount: 10000,
        payment_method: 'credit_card',
        gateway_provider: 'stripe'
      }
    end

    it 'formats successful validation results correctly' do
      handler.process_results(step, service_response, {})

      expect(step.results).to include(
        'payment_validated' => true,
        'payment_id' => 'pay_123456789',
        'eligibility_status' => 'eligible',
        'original_amount' => 10000,
        'payment_method' => 'credit_card',
        'gateway_provider' => 'stripe',
        'namespace' => 'payments'
      )
      expect(step.results['validation_timestamp']).to be_present
    end

    it 'handles result processing errors gracefully' do
      # Ensure task and step are created before we stub Time.current
      step # Force lazy evaluation
      
      # Now simulate an error during result processing
      allow(Time).to receive(:current).and_raise(StandardError, 'Time error')

      expect { handler.process_results(step, service_response, {}) }
        .to raise_error(Tasker::PermanentError, /Failed to process validation results/)
    end
  end

  describe 'input validation' do
    it 'properly normalizes hash keys to symbols for service calls' do
      string_key_context = {
        'payment_id' => 'pay_123',
        'refund_amount' => 1000,
        'refund_reason' => 'test'
      }
      
      string_task = create_test_task(
        name: 'process_refund',
        namespace: 'payments',
        context: string_key_context
      )
      
      string_step = string_task.workflow_steps.find { |s| s.name == 'validate_payment_eligibility' }

      MockPaymentGateway.stub_response(:validate_payment_eligibility, {
        status: 'eligible',
        payment_id: 'pay_123'
      })

      handler.process(string_task, string_task.workflow_steps, string_step)

      # Verify the mock service was called with the correct normalized inputs
      calls = MockPaymentGateway.calls_for(:validate_payment_eligibility)
      expect(calls.size).to eq(1)
      expect(calls.first[:args][:payment_id]).to eq('pay_123')
    end
  end
end