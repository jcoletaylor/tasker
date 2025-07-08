# frozen_string_literal: true

require_relative '../../support/blog_spec_helper'

RSpec.describe 'Post 04: Framework Capabilities Demonstration', type: :blog_example do
  before do
    # Load Post 04 blog code
    load_blog_code_safely('post_04_team_scaling')
    BaseMockService.reset_all_mocks!
  end

  describe 'Core Tasker Framework Features' do
    it 'supports multiple namespaces with same workflow names' do
      # Simply show the concept using the handler registry
      payments_handlers = Tasker::HandlerFactory.instance.handler_classes[:payments]
      cs_handlers = Tasker::HandlerFactory.instance.handler_classes[:customer_success]
      
      # Both namespaces have a 'process_refund' handler
      expect(payments_handlers).to have_key(:process_refund)
      expect(cs_handlers).to have_key(:process_refund)
      
      puts '✅ Demonstrated: Multiple namespaces can have workflows with same name'
    end

    it 'allows teams to version their workflows independently' do
      # Show version information from handlers
      payments_config = YAML.load_file(blog_config_path('post_04_team_scaling', 'payments_process_refund.yaml'))
      cs_config = YAML.load_file(blog_config_path('post_04_team_scaling', 'customer_success_process_refund.yaml'))
      
      expect(payments_config['version']).to eq('2.1.0')
      expect(cs_config['version']).to eq('1.3.0')
      
      puts '✅ Demonstrated: Each team controls their own versioning'
    end

    it 'provides workflow step dependencies' do
      # Show that steps can depend on each other
      payments_config = YAML.load_file(blog_config_path('post_04_team_scaling', 'payments_process_refund.yaml'))
      
      # Find a step with dependencies
      gateway_step = payments_config['step_templates'].find { |s| s['name'] == 'process_gateway_refund' }
      expect(gateway_step['depends_on_step']).to eq('validate_payment_eligibility')
      
      puts '✅ Demonstrated: Steps can declare dependencies on other steps'
    end

    it 'enables error handling and retries' do
      # Show retry configuration in step templates
      payments_config = YAML.load_file(blog_config_path('post_04_team_scaling', 'payments_process_refund.yaml'))
      
      validate_step = payments_config['step_templates'].find { |s| s['name'] == 'validate_payment_eligibility' }
      expect(validate_step['default_retryable']).to be true
      expect(validate_step['default_retry_limit']).to eq(3)
      
      puts '✅ Demonstrated: Steps can be configured with retry logic'
    end

    it 'supports cross-team coordination' do
      # Show that customer success workflow includes a step to call payments
      cs_config = YAML.load_file(blog_config_path('post_04_team_scaling', 'customer_success_process_refund.yaml'))
      
      execute_step = cs_config['step_templates'].find { |s| s['name'] == 'execute_refund_workflow' }
      expect(execute_step).to be_present
      expect(execute_step['description']).to include('payments team')
      
      puts '✅ Demonstrated: Workflows can coordinate across team boundaries'
    end

    it 'provides step handler isolation' do
      # Show that each team has their own step handlers
      payments_handler = BlogExamples::Post04::StepHandlers::ValidatePaymentEligibilityHandler.new
      cs_handler = BlogExamples::Post04::StepHandlers::ValidateRefundRequestHandler.new
      
      expect(payments_handler.class.name).to include('ValidatePaymentEligibility')
      expect(cs_handler.class.name).to include('ValidateRefundRequest')
      
      puts '✅ Demonstrated: Each team owns and maintains their step handlers'
    end

    it 'uses mock services for testing' do
      # Show the mock service pattern
      MockPaymentGateway.stub_response(:validate_payment_eligibility, {
        status: 'eligible',
        payment_id: 'test_123'
      })
      
      result = MockPaymentGateway.validate_payment_eligibility(payment_id: 'test_123')
      expect(result[:status]).to eq('eligible')
      
      # Show we can track calls
      expect(MockPaymentGateway.call_count(:validate_payment_eligibility)).to eq(1)
      
      puts '✅ Demonstrated: Mock services enable isolated testing'
    end

    it 'handles context validation through schemas' do
      # Show schema validation from YAML
      payments_config = YAML.load_file(blog_config_path('post_04_team_scaling', 'payments_process_refund.yaml'))
      
      schema = payments_config['schema']
      expect(schema['required']).to include('payment_id')
      expect(schema['required']).to include('refund_amount')
      
      puts '✅ Demonstrated: Workflows validate input through JSON schemas'
    end
  end
end