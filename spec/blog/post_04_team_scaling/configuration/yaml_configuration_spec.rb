# frozen_string_literal: true

require_relative '../../support/blog_spec_helper'

RSpec.describe 'Post 04: Team Scaling - YAML Configuration', type: :blog_example do
  before do
    # Load Post 04 blog code
    load_blog_code_safely('post_04_team_scaling')
  end

  describe 'Payments Team Configuration' do
    let(:payments_config_path) { blog_config_path('post_04_team_scaling', 'payments_process_refund.yaml') }
    let(:payments_config) { validate_yaml_config(payments_config_path) }

    it 'has valid payments configuration structure' do
      expect(payments_config).to include(
        'name' => 'process_refund',
        'namespace_name' => 'payments',
        'version' => '2.1.0',
        'task_handler_class' => 'Payments::ProcessRefundHandler',
        'description' => 'Process payment gateway refunds with direct API integration',
        'default_dependent_system' => 'payment_gateway'
      )
    end

    it 'has valid payments schema definition' do
      schema = payments_config['schema']
      expect(schema).to be_a(Hash)
      expect(schema['type']).to eq('object')
      expect(schema['required']).to include('payment_id', 'refund_amount')

      properties = schema['properties']
      expect(properties).to include('payment_id', 'refund_amount', 'refund_reason')
      expect(properties['payment_id']['type']).to eq('string')
      expect(properties['refund_amount']['type']).to eq('number')
      expect(properties['refund_amount']['minimum']).to eq(0)
    end

    it 'defines exactly 4 step templates for payments workflow' do
      step_templates = payments_config['step_templates']
      expect(step_templates).to be_an(Array)
      expect(step_templates.count).to eq(4)

      step_names = step_templates.map { |s| s['name'] }
      expect(step_names).to eq([
        'validate_payment_eligibility',
        'process_gateway_refund',
        'update_payment_records',
        'notify_customer'
      ])
    end

    it 'has correct payments step dependencies' do
      step_templates = payments_config['step_templates']

      # First step has no dependencies
      validate_step = step_templates.find { |s| s['name'] == 'validate_payment_eligibility' }
      expect(validate_step['depends_on_step']).to be_nil

      # Second step depends on first
      gateway_step = step_templates.find { |s| s['name'] == 'process_gateway_refund' }
      expect(gateway_step['depends_on_step']).to eq('validate_payment_eligibility')

      # Third step depends on second
      records_step = step_templates.find { |s| s['name'] == 'update_payment_records' }
      expect(records_step['depends_on_step']).to eq('process_gateway_refund')

      # Fourth step depends on third
      notify_step = step_templates.find { |s| s['name'] == 'notify_customer' }
      expect(notify_step['depends_on_step']).to eq('update_payment_records')
    end

    it 'has correct payments handler class references' do
      step_templates = payments_config['step_templates']

      step_templates.each do |step|
        expect(step['handler_class']).to start_with('BlogExamples::Post04::StepHandlers::')
        expect(step['handler_class']).to end_with('Handler')
      end
    end
  end

  describe 'Customer Success Team Configuration' do
    let(:cs_config_path) { blog_config_path('post_04_team_scaling', 'customer_success_process_refund.yaml') }
    let(:cs_config) { validate_yaml_config(cs_config_path) }

    it 'has valid customer success configuration structure' do
      expect(cs_config).to include(
        'name' => 'process_refund',
        'namespace_name' => 'customer_success',
        'version' => '1.3.0',
        'task_handler_class' => 'CustomerSuccess::ProcessRefundHandler',
        'description' => 'Process customer service refunds with approval workflow',
        'default_dependent_system' => 'customer_service_platform'
      )
    end

    it 'has valid customer success schema definition' do
      schema = cs_config['schema']
      expect(schema).to be_a(Hash)
      expect(schema['type']).to eq('object')
      expect(schema['required']).to include('ticket_id', 'customer_id', 'refund_amount')

      properties = schema['properties']
      expect(properties).to include('ticket_id', 'customer_id', 'refund_amount', 'requires_approval')
      expect(properties['ticket_id']['type']).to eq('string')
      expect(properties['customer_id']['type']).to eq('string')
      expect(properties['requires_approval']['type']).to eq('boolean')
      expect(properties['requires_approval']['default']).to be(true)
    end

    it 'defines exactly 5 step templates for customer success workflow' do
      step_templates = cs_config['step_templates']
      expect(step_templates).to be_an(Array)
      expect(step_templates.count).to eq(5)

      step_names = step_templates.map { |s| s['name'] }
      expect(step_names).to eq([
        'validate_refund_request',
        'check_refund_policy',
        'get_manager_approval',
        'execute_refund_workflow',
        'update_ticket_status'
      ])
    end

    it 'has correct customer success step dependencies' do
      step_templates = cs_config['step_templates']

      # First step has no dependencies
      validate_step = step_templates.find { |s| s['name'] == 'validate_refund_request' }
      expect(validate_step['depends_on_step']).to be_nil

      # Second step depends on first
      policy_step = step_templates.find { |s| s['name'] == 'check_refund_policy' }
      expect(policy_step['depends_on_step']).to eq('validate_refund_request')

      # Third step depends on second
      approval_step = step_templates.find { |s| s['name'] == 'get_manager_approval' }
      expect(approval_step['depends_on_step']).to eq('check_refund_policy')

      # Fourth step depends on third (the key cross-namespace step)
      workflow_step = step_templates.find { |s| s['name'] == 'execute_refund_workflow' }
      expect(workflow_step['depends_on_step']).to eq('get_manager_approval')

      # Fifth step depends on fourth
      ticket_step = step_templates.find { |s| s['name'] == 'update_ticket_status' }
      expect(ticket_step['depends_on_step']).to eq('execute_refund_workflow')
    end

    it 'has correct customer success handler class references' do
      step_templates = cs_config['step_templates']

      step_templates.each do |step|
        expect(step['handler_class']).to start_with('BlogExamples::Post04::StepHandlers::')
        expect(step['handler_class']).to end_with('Handler')
      end
    end

    it 'has longer timeout for manager approval step' do
      step_templates = cs_config['step_templates']
      approval_step = step_templates.find { |s| s['name'] == 'get_manager_approval' }

      expect(approval_step['handler_config']['timeout_seconds']).to eq(300) # 5 minutes
    end
  end

  describe 'Cross-Namespace Configuration Comparison' do
    let(:payments_config) { validate_yaml_config(blog_config_path('post_04_team_scaling', 'payments_process_refund.yaml')) }
    let(:cs_config) { validate_yaml_config(blog_config_path('post_04_team_scaling', 'customer_success_process_refund.yaml')) }

    it 'demonstrates same workflow name in different namespaces' do
      expect(payments_config['name']).to eq('process_refund')
      expect(cs_config['name']).to eq('process_refund')

      expect(payments_config['namespace_name']).to eq('payments')
      expect(cs_config['namespace_name']).to eq('customer_success')
    end

    it 'shows independent versioning per namespace' do
      expect(payments_config['version']).to eq('2.1.0')
      expect(cs_config['version']).to eq('1.3.0')

      # Versions are different, showing independent team evolution
      expect(payments_config['version']).not_to eq(cs_config['version'])
    end

    it 'shows different business logic per namespace' do
      payments_steps = payments_config['step_templates'].count
      cs_steps = cs_config['step_templates'].count

      expect(payments_steps).to eq(4) # Direct gateway integration
      expect(cs_steps).to eq(5) # Approval workflow + cross-namespace call

      # Different step counts show different business logic
      expect(payments_steps).not_to eq(cs_steps)
    end

    it 'shows different dependent systems per namespace' do
      expect(payments_config['default_dependent_system']).to eq('payment_gateway')
      expect(cs_config['default_dependent_system']).to eq('customer_service_platform')

      # Different systems show team-specific integrations
      expect(payments_config['default_dependent_system']).not_to eq(cs_config['default_dependent_system'])
    end

    it 'shows different schema requirements per namespace' do
      payments_required = payments_config['schema']['required']
      cs_required = cs_config['schema']['required']

      # Payments requires payment_id
      expect(payments_required).to include('payment_id')
      expect(cs_required).not_to include('payment_id')

      # Customer Success requires ticket_id and customer_id
      expect(cs_required).to include('ticket_id', 'customer_id')
      expect(payments_required).not_to include('ticket_id')
      expect(payments_required).not_to include('customer_id')
    end
  end

  describe 'Task Handler Configuration Loading' do
    it 'loads payments task handler configuration correctly' do
      handler = Payments::ProcessRefundHandler.new

      expect(handler.class.namespace_name).to eq('payments')
      expect(handler.class.version).to eq('2.1.0')
      expect(handler.class.description).to include('payment gateway refunds')
    end

    it 'loads customer success task handler configuration correctly' do
      handler = CustomerSuccess::ProcessRefundHandler.new

      expect(handler.class.namespace_name).to eq('customer_success')
      expect(handler.class.version).to eq('1.3.0')
      expect(handler.class.description).to include('approval workflow')
    end

    it 'shows different configurations for same workflow name' do
      payments_handler = Payments::ProcessRefundHandler.new
      cs_handler = CustomerSuccess::ProcessRefundHandler.new

      # Same workflow name
      expect(payments_handler.class.config['name']).to eq('process_refund')
      expect(cs_handler.class.config['name']).to eq('process_refund')

      # Different namespaces
      expect(payments_handler.class.namespace_name).to eq('payments')
      expect(cs_handler.class.namespace_name).to eq('customer_success')

      # Different versions
      expect(payments_handler.class.version).to eq('2.1.0')
      expect(cs_handler.class.version).to eq('1.3.0')
    end
  end
end
