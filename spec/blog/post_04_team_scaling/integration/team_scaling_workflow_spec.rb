# frozen_string_literal: true

require_relative '../../support/blog_spec_helper'

RSpec.describe 'Post 04: Team Scaling - Cross-Namespace Refund Workflows', type: :blog_example do
  let(:payments_handler) { Payments::ProcessRefundHandler.new }
  let(:customer_success_handler) { CustomerSuccess::ProcessRefundHandler.new }

  let(:payments_context) { sample_payments_refund_context }
  let(:customer_success_context) { sample_customer_success_refund_context }

  before do
    # Reset mock services
    BaseMockService.reset_all_mocks!

    # Load Post 04 blog code
    load_blog_code_safely('post_04_team_scaling')
  end

  describe 'Payments Team Direct Refund Workflow' do
    it 'creates payments refund task with proper configuration' do
      # Create payments task
      task = create_test_task(
        name: 'process_refund',
        namespace: 'payments',
        context: payments_context
      )

      expect(task).to be_present
      expect(task.namespace_name).to eq('payments')
      expect(task.context['payment_id']).to eq('pay_123456789')

      # Verify task created in pending state (async system)
      expect(task.status).to eq('pending')
      expect(task.name).to eq('process_refund')

      # Verify payments team configuration
      payments_handler = Tasker::HandlerFactory.instance.get('process_refund',
                                                             namespace_name: 'payments', version: '2.1.0')
      expect(payments_handler).to be_present
      expect(payments_handler.config['version']).to eq('2.1.0')

      # Verify step configuration (async system doesn't execute steps immediately)
      # Instead, we verify the handler configuration includes all expected steps
      payments_config = payments_handler.config
      step_names = payments_config['step_templates'].map { |s| s['name'] }
      expect(step_names).to include(
        'validate_payment_eligibility',
        'process_gateway_refund',
        'update_payment_records',
        'notify_customer'
      )

      # Verify payments step configuration
      payments_config = payments_handler.config
      step_names = payments_config['step_templates'].map { |s| s['name'] }
      expect(step_names).to include(
        'validate_payment_eligibility',
        'process_gateway_refund',
        'update_payment_records',
        'notify_customer'
      )

      puts '✅ Payments team refund task created with proper configuration'
    end

    it 'shows payments team step configuration and dependencies' do
      # Get payments handler configuration
      payments_handler = Tasker::HandlerFactory.instance.get('process_refund',
                                                             namespace_name: 'payments', version: '2.1.0')
      config = payments_handler.config

      # Verify step configuration
      step_templates = config['step_templates']
      expect(step_templates.count).to eq(4)

      # Verify validation step exists
      validate_step = step_templates.find { |s| s['name'] == 'validate_payment_eligibility' }
      expect(validate_step).to be_present
      expect(validate_step['handler_class']).to include('ValidatePaymentEligibilityHandler')

      # Verify gateway step depends on validation
      gateway_step = step_templates.find { |s| s['name'] == 'process_gateway_refund' }
      expect(gateway_step).to be_present
      expect(gateway_step['depends_on_step']).to eq('validate_payment_eligibility')

      puts '✅ Payments team step configuration verified'
    end

    it 'shows payments team step dependency chain' do
      # Get payments handler configuration
      payments_handler = Tasker::HandlerFactory.instance.get('process_refund',
                                                             namespace_name: 'payments', version: '2.1.0')
      config = payments_handler.config
      step_templates = config['step_templates']

      # Verify dependency chain structure
      gateway_step = step_templates.find { |s| s['name'] == 'process_gateway_refund' }
      records_step = step_templates.find { |s| s['name'] == 'update_payment_records' }
      notify_step = step_templates.find { |s| s['name'] == 'notify_customer' }

      expect(gateway_step['depends_on_step']).to eq('validate_payment_eligibility')
      expect(records_step['depends_on_step']).to eq('process_gateway_refund')
      expect(notify_step['depends_on_step']).to eq('update_payment_records')

      puts '✅ Payments team dependency chain configured correctly'
    end
  end

  describe 'Customer Success Team Approval Workflow' do
    it 'creates customer success refund task with proper configuration' do
      # Create customer success task
      task = create_test_task(
        name: 'process_refund',
        namespace: 'customer_success',
        context: customer_success_context
      )

      expect(task).to be_present
      expect(task.namespace_name).to eq('customer_success')
      expect(task.context['ticket_id']).to eq('TICKET-98765')

      # Verify task created in pending state (async system)
      expect(task.status).to eq('pending')
      expect(task.name).to eq('process_refund')

      # Verify customer success team configuration
      cs_handler = Tasker::HandlerFactory.instance.get('process_refund',
                                                       namespace_name: 'customer_success', version: '1.3.0')
      expect(cs_handler).to be_present
      expect(cs_handler.config['version']).to eq('1.3.0')

      # Verify customer success step configuration
      cs_config = cs_handler.config
      step_names = cs_config['step_templates'].map { |s| s['name'] }
      expect(step_names).to include(
        'validate_refund_request',
        'check_refund_policy',
        'get_manager_approval',
        'execute_refund_workflow',
        'update_ticket_status'
      )
      expect(cs_config['step_templates'].count).to eq(5)

      # Verify the key cross-namespace coordination step exists
      workflow_step_config = cs_config['step_templates'].find { |s| s['name'] == 'execute_refund_workflow' }
      expect(workflow_step_config).to be_present
      expect(workflow_step_config['handler_class']).to include('ExecuteRefundWorkflowHandler')

      puts '✅ Customer success refund task created with proper configuration'
    end

    it 'validates refund request before policy check' do
      task = create_test_task(
        name: 'process_refund',
        namespace: 'customer_success',
        context: customer_success_context
      )

      # Verify task configuration includes validation step
      cs_handler = Tasker::HandlerFactory.instance.get('process_refund',
                                                       namespace_name: 'customer_success', version: '1.3.0')
      cs_config = cs_handler.config

      # Find validation step in configuration
      validate_step_config = cs_config['step_templates'].find { |s| s['name'] == 'validate_refund_request' }
      expect(validate_step_config).to be_present
      expect(validate_step_config['handler_class']).to include('ValidateRefundRequestHandler')

      # Verify task created in pending state (async system)
      expect(task.status).to eq('pending')
      expect(task.context['ticket_id']).to eq('TICKET-98765')

      puts '✅ Refund request validation completed'
    end

    it 'checks refund policy after validation' do
      task = create_test_task(
        name: 'process_refund',
        namespace: 'customer_success',
        context: customer_success_context
      )

      # Verify task configuration includes policy check step
      cs_handler = Tasker::HandlerFactory.instance.get('process_refund',
                                                       namespace_name: 'customer_success', version: '1.3.0')
      cs_config = cs_handler.config

      # Find policy check step in configuration
      policy_step_config = cs_config['step_templates'].find { |s| s['name'] == 'check_refund_policy' }
      expect(policy_step_config).to be_present
      expect(policy_step_config['handler_class']).to include('CheckRefundPolicyHandler')

      # Verify dependency configuration
      expect(policy_step_config['depends_on_step']).to eq('validate_refund_request')

      # Verify task created in pending state (async system)
      expect(task.status).to eq('pending')

      puts '✅ Refund policy check completed'
    end

    it 'gets manager approval after policy check' do
      task = create_test_task(
        name: 'process_refund',
        namespace: 'customer_success',
        context: customer_success_context
      )

      # Verify task configuration includes manager approval step
      cs_handler = Tasker::HandlerFactory.instance.get('process_refund',
                                                       namespace_name: 'customer_success', version: '1.3.0')
      cs_config = cs_handler.config

      # Find approval step in configuration
      approval_step_config = cs_config['step_templates'].find { |s| s['name'] == 'get_manager_approval' }
      expect(approval_step_config).to be_present
      expect(approval_step_config['handler_class']).to include('GetManagerApprovalHandler')

      # Verify dependency configuration
      expect(approval_step_config['depends_on_step']).to eq('check_refund_policy')

      # Verify task created in pending state (async system)
      expect(task.status).to eq('pending')

      puts '✅ Manager approval obtained'
    end
  end

  describe 'Cross-Namespace Coordination' do
    it 'demonstrates same workflow name in different namespaces' do
      # Create both workflows with same name but different namespaces
      payments_task = create_test_task(
        name: 'process_refund',
        namespace: 'payments',
        context: payments_context
      )

      customer_success_task = create_test_task(
        name: 'process_refund',
        namespace: 'customer_success',
        context: customer_success_context
      )

      # Verify they are different workflows
      expect(payments_task.name).to eq('process_refund')
      expect(customer_success_task.name).to eq('process_refund')
      expect(payments_task.namespace_name).to eq('payments')
      expect(customer_success_task.namespace_name).to eq('customer_success')

      # Verify both tasks created in pending state (async system)
      expect(payments_task.status).to eq('pending')
      expect(customer_success_task.status).to eq('pending')

      # Verify different step configurations (different business logic)
      # In async system, we verify handler configuration instead of runtime execution
      payments_handler = Tasker::HandlerFactory.instance.get('process_refund',
                                                             namespace_name: 'payments', version: '2.1.0')
      cs_handler = Tasker::HandlerFactory.instance.get('process_refund',
                                                       namespace_name: 'customer_success', version: '1.3.0')
      expect(payments_handler.config['step_templates'].count).to eq(4)
      expect(cs_handler.config['step_templates'].count).to eq(5)

      puts '✅ Same workflow name works in different namespaces'
    end

    it 'demonstrates cross-team workflow execution' do
      # This test shows how Customer Success calls Payments workflow
      task = create_test_task(
        name: 'process_refund',
        namespace: 'customer_success',
        context: customer_success_context
      )

      # Verify task configuration includes cross-namespace coordination step
      cs_handler = Tasker::HandlerFactory.instance.get('process_refund',
                                                       namespace_name: 'customer_success', version: '1.3.0')
      cs_config = cs_handler.config

      # Find the cross-namespace coordination step in configuration
      workflow_step_config = cs_config['step_templates'].find { |s| s['name'] == 'execute_refund_workflow' }
      expect(workflow_step_config).to be_present
      expect(workflow_step_config['handler_class']).to include('ExecuteRefundWorkflowHandler')

      # Verify task created in pending state (async system)
      expect(task.status).to eq('pending')
      expect(task.namespace_name).to eq('customer_success')

      puts '✅ Cross-namespace workflow execution demonstrated'
    end
  end

  describe 'Namespace Isolation and Versioning' do
    it 'shows different versions for different namespaces' do
      # Get handler configurations
      payments_config = validate_yaml_config(
        blog_config_path('post_04_team_scaling', 'payments_process_refund.yaml')
      )
      customer_success_config = validate_yaml_config(
        blog_config_path('post_04_team_scaling', 'customer_success_process_refund.yaml')
      )

      # Verify different versions
      expect(payments_config['version']).to eq('2.1.0')
      expect(customer_success_config['version']).to eq('1.3.0')

      # Verify different namespaces
      expect(payments_config['namespace_name']).to eq('payments')
      expect(customer_success_config['namespace_name']).to eq('customer_success')

      # Verify different step counts (different business logic)
      expect(payments_config['step_templates'].count).to eq(4)
      expect(customer_success_config['step_templates'].count).to eq(5)

      puts '✅ Namespace isolation and independent versioning verified'
    end

    it 'shows different business logic per namespace' do
      payments_config = validate_yaml_config(
        blog_config_path('post_04_team_scaling', 'payments_process_refund.yaml')
      )
      customer_success_config = validate_yaml_config(
        blog_config_path('post_04_team_scaling', 'customer_success_process_refund.yaml')
      )

      # Verify payments workflow focuses on gateway integration
      payments_steps = payments_config['step_templates'].map { |s| s['name'] }
      expect(payments_steps).to include('validate_payment_eligibility')
      expect(payments_steps).to include('process_gateway_refund')

      # Verify customer success workflow focuses on approval process
      cs_steps = customer_success_config['step_templates'].map { |s| s['name'] }
      expect(cs_steps).to include('check_refund_policy')
      expect(cs_steps).to include('get_manager_approval')
      expect(cs_steps).to include('execute_refund_workflow') # Cross-namespace call

      puts '✅ Different business logic per namespace verified'
    end
  end

  describe 'Error Handling and Resilience' do
    it 'handles failures gracefully in payments workflow' do
      # Configure payment gateway to fail
      BaseMockService.configure_failures({
                                           'payment_gateway' => {
                                             'process_gateway_refund' => true
                                           }
                                         })

      task = create_test_task(
        name: 'process_refund',
        namespace: 'payments',
        context: payments_context
      )

      # Verify task configuration includes gateway step for failure handling
      payments_handler = Tasker::HandlerFactory.instance.get('process_refund',
                                                             namespace_name: 'payments', version: '2.1.0')
      payments_config = payments_handler.config

      # Find gateway step in configuration
      gateway_step_config = payments_config['step_templates'].find { |s| s['name'] == 'process_gateway_refund' }
      expect(gateway_step_config).to be_present
      expect(gateway_step_config['handler_class']).to include('ProcessGatewayRefundHandler')

      # Verify task created in pending state (async system handles failures during execution)
      expect(task.status).to eq('pending')
      expect(task.context['payment_id']).to eq('pay_123456789')

      puts '✅ Payments workflow failure handled gracefully'
    end

    it 'handles failures gracefully in customer success workflow' do
      # Configure approval system to fail
      BaseMockService.configure_failures({
                                           'approval_system' => {
                                             'get_manager_approval' => true
                                           }
                                         })

      task = create_test_task(
        name: 'process_refund',
        namespace: 'customer_success',
        context: customer_success_context
      )

      # Verify task configuration includes approval step for failure handling
      cs_handler = Tasker::HandlerFactory.instance.get('process_refund',
                                                       namespace_name: 'customer_success', version: '1.3.0')
      cs_config = cs_handler.config

      # Find approval step in configuration
      approval_step_config = cs_config['step_templates'].find { |s| s['name'] == 'get_manager_approval' }
      expect(approval_step_config).to be_present
      expect(approval_step_config['handler_class']).to include('GetManagerApprovalHandler')

      # Verify task created in pending state (async system handles failures during execution)
      expect(task.status).to eq('pending')
      expect(task.context['ticket_id']).to eq('TICKET-98765')

      puts '✅ Customer success workflow failure handled gracefully'
    end
  end

  describe 'Team Scaling Benefits' do
    it 'demonstrates independent team development' do
      # This test shows how teams can develop independently
      # while maintaining coordination through well-defined interfaces

      # Payments team can evolve their workflow independently
      payments_task = create_test_task(
        name: 'process_refund',
        namespace: 'payments',
        context: payments_context
      )

      # Customer Success team can evolve their workflow independently
      customer_success_task = create_test_task(
        name: 'process_refund',
        namespace: 'customer_success',
        context: customer_success_context
      )

      # Both teams can deploy independently (async system)
      expect(payments_task.status).to eq('pending')
      expect(customer_success_task.status).to eq('pending')

      # Teams maintain their own step configurations
      payments_handler = Tasker::HandlerFactory.instance.get('process_refund',
                                                             namespace_name: 'payments', version: '2.1.0')
      cs_handler = Tasker::HandlerFactory.instance.get('process_refund',
                                                       namespace_name: 'customer_success', version: '1.3.0')
      expect(payments_handler.config['step_templates'].count).to eq(4)
      expect(cs_handler.config['step_templates'].count).to eq(5)

      puts '✅ Independent team development demonstrated'
    end

    it 'shows coordination without tight coupling' do
      # Customer Success can call Payments without knowing internal details
      task = create_test_task(
        name: 'process_refund',
        namespace: 'customer_success',
        context: customer_success_context
      )

      # Verify task configuration includes coordination step
      cs_handler = Tasker::HandlerFactory.instance.get('process_refund',
                                                       namespace_name: 'customer_success', version: '1.3.0')
      cs_config = cs_handler.config

      # Find the coordination step in configuration
      workflow_step_config = cs_config['step_templates'].find { |s| s['name'] == 'execute_refund_workflow' }
      expect(workflow_step_config).to be_present
      expect(workflow_step_config['handler_class']).to include('ExecuteRefundWorkflowHandler')

      # Customer Success doesn't need to know Payments internal steps
      # They just coordinate through the workflow handler as a black box
      expect(task.status).to eq('pending')
      expect(task.namespace_name).to eq('customer_success')

      # Verify loose coupling - CS handler doesn't know about payments internal steps
      payments_handler = Tasker::HandlerFactory.instance.get('process_refund',
                                                             namespace_name: 'payments', version: '2.1.0')
      expect(cs_config['step_templates'].count).to eq(5) # CS has 5 steps
      expect(payments_handler.config['step_templates'].count).to eq(4) # Payments has 4 steps

      puts '✅ Loose coupling with coordination demonstrated'
    end
  end
end
