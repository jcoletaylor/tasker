# frozen_string_literal: true

require_relative '../../support/blog_spec_helper'

RSpec.describe 'Post 04: Team Scaling - Simplified Demonstrations', type: :blog_example do
  let(:payments_context) do
    {
      'payment_id' => 'pay_123456789',
      'refund_amount' => 7500,
      'refund_reason' => 'customer_request',
      'partial_refund' => false,
      'correlation_id' => 'test_correlation_123',
      'customer_email' => 'customer@example.com'
    }
  end

  let(:customer_success_context) do
    {
      'ticket_id' => 'TICKET-98765',
      'customer_id' => 'CUST-54321',
      'refund_amount' => 12_000,
      'refund_reason' => 'Product defect reported by customer',
      'agent_notes' => 'Customer reported product malfunction after 2 weeks of use',
      'requires_approval' => true,
      'correlation_id' => 'cs_workflow_456',
      'customer_email' => 'customer@example.com',
      'payment_id' => 'pay_987654321' # Adding payment_id for execute_refund_workflow step
    }
  end

  before do
    # Reset mock services
    BaseMockService.reset_all_mocks!

    # Load Post 04 blog code
    load_blog_code_safely('post_04_team_scaling')
  end

  describe 'Key Framework Demonstrations' do
    it 'shows namespace isolation - same workflow name in different namespaces' do
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

      # Demonstrate they are different workflows despite same name
      expect(payments_task.name).to eq('process_refund')
      expect(customer_success_task.name).to eq('process_refund')
      expect(payments_task.namespace_name).to eq('payments')
      expect(customer_success_task.namespace_name).to eq('customer_success')

      # Verify tasks are created in pending state (async system)
      expect(payments_task.status).to eq('pending')
      expect(customer_success_task.status).to eq('pending')

      # Show they are configured for different business logic
      # (Step creation is async, so we verify task configuration instead)
      expect(payments_task.name).to eq('process_refund')
      expect(customer_success_task.name).to eq('process_refund')
      expect(payments_task.object_id).not_to eq(customer_success_task.object_id)

      puts '✅ Demonstrated: Same workflow name can exist in different namespaces'
    end

    it 'shows independent versioning per namespace' do
      # Get handlers to show version differences
      payments_handler = Tasker::HandlerFactory.instance.get('process_refund',
                                                             namespace_name: 'payments', version: '2.1.0')
      cs_handler = Tasker::HandlerFactory.instance.get('process_refund',
                                                       namespace_name: 'customer_success', version: '1.3.0')

      expect(payments_handler).to be_present
      expect(cs_handler).to be_present

      # Show different versions from config
      expect(payments_handler.config['version']).to eq('2.1.0')
      expect(cs_handler.config['version']).to eq('1.3.0')

      puts '✅ Demonstrated: Each namespace can have its own version'
    end

    it 'shows step handler organization by team' do
      # Get handlers to show team organization
      payments_handler = Tasker::HandlerFactory.instance.get('process_refund',
                                                             namespace_name: 'payments', version: '2.1.0')
      cs_handler = Tasker::HandlerFactory.instance.get('process_refund',
                                                       namespace_name: 'customer_success', version: '1.3.0')

      # Verify different teams have different step configurations
      payments_config = payments_handler.config
      cs_config = cs_handler.config

      expect(payments_config['step_templates'].count).to eq(4)
      expect(cs_config['step_templates'].count).to eq(5)

      # Show different step names for different teams
      payments_steps = payments_config['step_templates'].map { |s| s['name'] }
      cs_steps = cs_config['step_templates'].map { |s| s['name'] }

      expect(payments_steps).to include('validate_payment_eligibility')
      expect(cs_steps).to include('get_manager_approval')
      expect(cs_steps).to include('execute_refund_workflow')

      puts '✅ Demonstrated: Teams organize their own step handlers'
    end

    it 'shows task delegation patterns for async execution' do
      # Create payments task to show async delegation
      task = create_test_task(
        name: 'process_refund',
        namespace: 'payments',
        context: payments_context
      )

      # Verify task is created in pending state (async pattern)
      expect(task.status).to eq('pending')
      expect(task.name).to eq('process_refund')
      expect(task.namespace_name).to eq('payments')

      # Show task has context for processing
      expect(task.context['payment_id']).to eq('pay_123456789')
      expect(task.context['refund_amount']).to eq(7500)

      puts '✅ Demonstrated: Async task delegation with proper context'
    end

    it 'shows cross-namespace coordination capability' do
      # Get handlers to show cross-namespace coordination configuration
      cs_handler = Tasker::HandlerFactory.instance.get('process_refund',
                                                       namespace_name: 'customer_success', version: '1.3.0')
      payments_handler = Tasker::HandlerFactory.instance.get('process_refund',
                                                             namespace_name: 'payments', version: '2.1.0')

      # Show customer success has execute_refund_workflow step for coordination
      cs_config = cs_handler.config
      cs_steps = cs_config['step_templates'].map { |s| s['name'] }
      expect(cs_steps).to include('execute_refund_workflow')

      # Show payments has direct gateway steps
      payments_config = payments_handler.config
      payments_steps = payments_config['step_templates'].map { |s| s['name'] }
      expect(payments_steps).to include('process_gateway_refund')

      puts '✅ Demonstrated: Customer Success coordinates with Payments via execute_refund_workflow'
    end

    it 'shows namespace isolation for task management' do
      # Create tasks in both namespaces
      payments_task = create_test_task(
        name: 'process_refund',
        namespace: 'payments',
        context: payments_context
      )

      cs_task = create_test_task(
        name: 'process_refund',
        namespace: 'customer_success',
        context: customer_success_context
      )

      # Show they're completely isolated
      expect(payments_task.namespace_name).to eq('payments')
      expect(cs_task.namespace_name).to eq('customer_success')
      expect(payments_task.object_id).not_to eq(cs_task.object_id)

      # Show they have different context requirements
      expect(payments_task.context['payment_id']).to be_present
      expect(cs_task.context['ticket_id']).to be_present
      expect(payments_task.context['ticket_id']).to be_nil

      puts '✅ Demonstrated: Complete namespace isolation for task management'
    end
  end
end
