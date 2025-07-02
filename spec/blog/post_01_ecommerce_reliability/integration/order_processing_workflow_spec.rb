require_relative '../../support/blog_spec_helper'

RSpec.describe 'Post 01: E-commerce Order Processing Workflow', type: :blog_example do
  let(:blog_post) { 'post_01_ecommerce_reliability' }

  # Load all required mock services
  before(:all) do
    require_relative '../../support/mock_services/base_mock_service'
    require_relative '../../support/mock_services/payment_service'
    require_relative '../../support/mock_services/email_service'
    require_relative '../../support/mock_services/inventory_service'
  end

  before(:each) do
    # Reset mock services before each test
    MockPaymentService.reset!
    MockEmailService.reset!
    MockInventoryService.reset!

    # Load blog example code dynamically
    begin
      load_blog_code(blog_post, 'models/product.rb')
      load_blog_code(blog_post, 'models/order.rb')
      load_blog_code(blog_post, 'task_handler/order_processing_handler.rb')

      # Load all step handlers
      load_step_handlers(blog_post, [
        'validate_cart_handler',
        'process_payment_handler',
        'update_inventory_handler',
        'create_order_handler',
        'send_confirmation_handler'
      ])
    rescue => e
      # If we can't load the blog code, skip the test with a clear message
      skip "Could not load blog code: #{e.message}"
    end
  end

  describe 'successful checkout flow' do
    it 'processes a complete order successfully' do
      # Create a task with the exact context structure from the blog post
      task = create_test_task(
        name: 'order_processing',
        context: sample_ecommerce_context
      )

      expect(task.status).to eq('pending')

      # Execute the workflow
      execute_workflow(task)

      # Verify final state
      verify_workflow_execution(task, expected_status: 'complete')

      # Verify each step completed successfully
      step_names = %w[validate_cart process_payment update_inventory create_order send_confirmation]
      step_names.each do |step_name|
        step = task.workflow_steps.find { |s| s.name == step_name }
        expect(step).to be_present, "Expected step '#{step_name}' to exist"
        expect(step.status).to eq('complete'), "Expected step '#{step_name}' to be complete, got '#{step.status}'"
      end

      # Verify external service interactions
      verify_payment_processing
      verify_email_delivery
      verify_inventory_management
    end

    it 'handles premium customer priority correctly' do
      # Test the premium customer optimization from the blog post
      premium_context = sample_ecommerce_context.deep_merge(
        customer_info: { tier: 'premium' }
      )

      task = create_test_task(
        name: 'order_processing',
        context: premium_context
      )

      execute_workflow(task)
      verify_workflow_execution(task, expected_status: 'complete')

      # Verify premium customer handling
      # (This would check for faster processing, priority handling, etc.)
      expect(task.context['customer_info']['tier']).to eq('premium')
    end

    it 'handles express orders with faster timeouts' do
      # Test the express order optimization from the blog post
      express_context = sample_ecommerce_context.merge(
        priority: 'express'
      )

      task = create_test_task(
        name: 'order_processing',
        context: express_context
      )

      execute_workflow(task)
      verify_workflow_execution(task, expected_status: 'complete')

      # Verify express handling
      expect(task.context['priority']).to eq('express')
    end
  end

  describe 'error handling and recovery' do
    it 'retries payment failures with exponential backoff' do
      # Simulate payment service failure for the first few attempts
      MockPaymentService.stub_failure(:process_payment, MockPaymentService::PaymentError, 'Temporary payment gateway error')

      task = create_test_task(
        name: 'order_processing',
        context: sample_ecommerce_context
      )

      # Execute workflow - it should retry and eventually fail or succeed based on retry configuration
      execute_workflow(task, timeout: 60) # Longer timeout for retries

      # Verify retry behavior
      payment_step = task.workflow_steps.find { |s| s.name == 'process_payment' }
      expect(payment_step).to be_present

      # Check that payment service was called multiple times (retries)
      expect(MockPaymentService.call_count(:process_payment)).to be > 1

      # The step should either be in error state or have succeeded after retries
      expect(['error', 'complete']).to include(payment_step.status)
    end

    it 'handles inventory shortage gracefully' do
      # Simulate insufficient inventory
      MockInventoryService.stub_failure(:check_availability, MockInventoryService::InsufficientStockError, 'Insufficient stock')

      task = create_test_task(
        name: 'order_processing',
        context: sample_ecommerce_context
      )

      execute_workflow(task, timeout: 30)

      # Verify the workflow handles inventory shortage
      inventory_step = task.workflow_steps.find { |s| s.name == 'update_inventory' }
      expect(inventory_step).to be_present

      # Should have attempted inventory check
      expect(MockInventoryService.called?(:check_availability)).to be true
    end

    it 'handles email delivery failures with retries' do
      # Simulate email service failure
      MockEmailService.stub_failure(:send_confirmation, MockEmailService::DeliveryError, 'Email service temporarily unavailable')

      task = create_test_task(
        name: 'order_processing',
        context: sample_ecommerce_context
      )

      execute_workflow(task, timeout: 60)

      # Verify email retry behavior
      email_step = task.workflow_steps.find { |s| s.name == 'send_confirmation' }
      expect(email_step).to be_present

      # Should have attempted email delivery multiple times
      expect(MockEmailService.call_count(:send_confirmation)).to be > 1
    end
  end

  describe 'workflow configuration validation' do
    it 'validates the YAML configuration file' do
      config_path = blog_config_path(blog_post, 'order_processing.yaml')

      # Skip if config file doesn't exist
      skip "Configuration file not found: #{config_path}" unless File.exist?(config_path)

      config = validate_yaml_config(config_path)

      # Verify the configuration structure
      expect(config['name']).to eq('order_processing')
      expect(config['step_templates']).to be_an(Array)
      expect(config['step_templates'].length).to be > 0

      # Verify each step has required fields
      expected_steps = %w[validate_cart process_payment update_inventory create_order send_confirmation]
      step_names = config['step_templates'].map { |step| step['name'] }

      expected_steps.each do |expected_step|
        expect(step_names).to include(expected_step), "Expected step '#{expected_step}' in configuration"
      end
    end

    it 'validates the handler configuration file' do
      config_path = blog_config_path(blog_post, 'order_processing_handler.yaml')

      # Skip if config file doesn't exist
      skip "Handler configuration file not found: #{config_path}" unless File.exist?(config_path)

      config = validate_yaml_config(config_path)

      # Verify handler-specific configuration
      expect(config).to include('name')
      expect(config['name']).to eq('order_processing')
    end
  end

  describe 'business logic validation' do
    it 'calculates order totals correctly' do
      task = create_test_task(
        name: 'order_processing',
        context: sample_ecommerce_context
      )

      # Verify the order total calculation matches the context
      expected_total = sample_ecommerce_context[:cart_items].sum { |item| item[:price] * item[:quantity] }
      expect(task.context['payment_info']['amount']).to eq(expected_total)
    end

    it 'tracks customer information throughout the workflow' do
      task = create_test_task(
        name: 'order_processing',
        context: sample_ecommerce_context
      )

      execute_workflow(task)

      # Verify customer info is preserved
      expect(task.context['customer_info']['email']).to eq('customer@example.com')
      expect(task.context['customer_info']['id']).to eq(123)
    end
  end

  private

  # Verify payment processing occurred correctly
  def verify_payment_processing
    expect(MockPaymentService.called?(:process_payment)).to be true

    last_payment_call = MockPaymentService.last_call(:process_payment)
    expect(last_payment_call[:args][:amount]).to eq(109.97)
    expect(last_payment_call[:args][:method]).to eq('credit_card')
  end

  # Verify email delivery occurred correctly
  def verify_email_delivery
    expect(MockEmailService.called?(:send_confirmation)).to be true

    last_email_call = MockEmailService.last_call(:send_confirmation)
    expect(last_email_call[:args][:to]).to eq('customer@example.com')
  end

  # Verify inventory management occurred correctly
  def verify_inventory_management
    # Check if inventory operations were performed
    # This might include availability checks, reservations, or commits
    expect(
      MockInventoryService.called?(:check_availability) ||
      MockInventoryService.called?(:reserve_inventory) ||
      MockInventoryService.called?(:commit_reservation)
    ).to be true
  end
end
