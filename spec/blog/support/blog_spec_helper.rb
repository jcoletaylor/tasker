# frozen_string_literal: true

# Blog Example Validation Helper
# Provides utilities for testing blog post code examples against Tasker Engine
require 'rails_helper'

# Load mock services
require_relative 'mock_services/base_mock_service'
require_relative 'mock_services/payment_service'
require_relative 'mock_services/email_service'
require_relative 'mock_services/inventory_service'
require_relative 'mock_services/data_warehouse_service'
require_relative 'mock_services/dashboard_service'
require_relative 'mock_services/user_service'
require_relative 'mock_services/billing_service'
require_relative 'mock_services/preferences_service'
require_relative 'mock_services/notification_service'
require_relative 'mock_services/metrics_service'
require_relative 'mock_services/error_reporting_service'

module BlogSpecHelpers
  # Path to the blog fixtures within the Tasker repository
  BLOG_FIXTURES_ROOT = File.join(File.dirname(__FILE__), '..', 'fixtures').freeze

  # Load blog example code dynamically from fixtures
  # @param post_name [String] The blog post directory name (e.g., 'post_01_ecommerce_reliability')
  # @param file_path [String] The relative path within the fixtures (e.g., 'step_handlers/validate_cart_handler.rb')
  def load_blog_code(post_name, file_path)
    full_path = File.join(BLOG_FIXTURES_ROOT, post_name, file_path)

    raise "Blog code file not found: #{full_path}" unless File.exist?(full_path)

    # Load the file using 'load' instead of 'require' to allow reloading
    # This helps avoid conflicts and allows for better isolation
    begin
      load full_path
      track_loaded_file(full_path)
    rescue StandardError => e
      # If there's an enum conflict or other loading issue, provide a helpful error
      if e.message.include?('enum') || e.message.include?('already defined')
        raise "Blog code loading conflict (likely enum collision): #{e.message}. This is expected during development - the blog examples use models that conflict with Tasker's existing models."
      end

      raise e
    end
  end

  # Load all step handlers for a blog post
  # @param post_name [String] The blog post directory name
  # @param handler_names [Array<String>] List of handler file names (without .rb extension)
  def load_step_handlers(post_name, handler_names)
    handler_names.each do |handler_name|
      load_blog_code(post_name, "step_handlers/#{handler_name}.rb")
    end
  end

  # Create a test task with realistic context for blog examples
  # @param name [String] Task name
  # @param context [Hash] Task context data
  # @param namespace [String] Task namespace (defaults to 'blog_examples')
  # @param version [String] Task version (defaults to latest available)
  def create_test_task(name:, context:, namespace: 'blog_examples', version: nil)
    task_request = Tasker::Types::TaskRequest.new(
      name: name,
      namespace: namespace,
      context: context
    )

    # Get the handler and initialize the task
    # If no version specified, use defaults based on namespace
    handler = if version
                Tasker::HandlerFactory.instance.get(name, namespace_name: namespace, version: version)
              elsif namespace == 'blog_examples'
                # Blog examples use version 1.0.0 from YAML configurations
                Tasker::HandlerFactory.instance.get(name, namespace_name: namespace, version: '1.0.0')
              elsif namespace == 'payments'
                # Post 04 payments namespace uses version 2.1.0
                Tasker::HandlerFactory.instance.get(name, namespace_name: namespace, version: '2.1.0')
              elsif namespace == 'customer_success'
                # Post 04 customer_success namespace uses version 1.3.0
                Tasker::HandlerFactory.instance.get(name, namespace_name: namespace, version: '1.3.0')
              else
                Tasker::HandlerFactory.instance.get(name, namespace_name: namespace)
              end
    task = handler.initialize_task!(task_request)

    # Only save if there are no validation errors (save! would clear them)
    task.save! if task.errors.empty? && task.respond_to?(:save!)
    task
  end

  # Validate YAML configuration file
  # @param config_path [String] Path to the YAML configuration file
  # @return [Hash] Parsed configuration
  def validate_yaml_config(config_path)
    raise "Configuration file not found: #{config_path}" unless File.exist?(config_path)

    config = YAML.load_file(config_path)

    # Basic validation
    expect(config).to be_a(Hash)
    expect(config).to include('name')
    expect(config).to include('step_templates')
    expect(config['step_templates']).to be_an(Array)

    # Validate each step template has required fields
    config['step_templates'].each_with_index do |step, index|
      expect(step).to include('name'), "Step #{index} missing 'name' field"
      expect(step).to include('handler_class'), "Step #{index} missing 'handler_class' field"
    end

    config
  end

  # Execute a workflow and wait for completion
  # @param task [Tasker::Task] The task to execute
  # @param timeout [Integer] Maximum wait time in seconds (default: 30)
  def execute_workflow(task, timeout: 30)
    # Get the task handler for the task
    # For blog examples, use version 1.0.0 from YAML configurations
    # For Post 04, use specific versions from YAML
    handler = case task.namespace_name
              when 'blog_examples'
                Tasker::HandlerFactory.instance.get(task.name, namespace_name: task.namespace_name, version: '1.0.0')
              when 'payments'
                Tasker::HandlerFactory.instance.get(task.name, namespace_name: task.namespace_name, version: '2.1.0')
              when 'customer_success'
                Tasker::HandlerFactory.instance.get(task.name, namespace_name: task.namespace_name, version: '1.3.0')
              else
                Tasker::HandlerFactory.instance.get(task.name, namespace_name: task.namespace_name)
              end

    puts "Debug: About to execute handler.handle(task) for task #{task.name}"
    puts "Debug: Task status before handler.handle: #{task.status}"
    puts "Debug: Handler class: #{handler.class}"

    # Execute the workflow using the task handler
    begin
      result = handler.handle(task)
      puts "Debug: Handler.handle returned: #{result.inspect}"
    rescue StandardError => e
      puts "Debug: Handler.handle raised error: #{e.class} - #{e.message}"
      puts "Debug: Error backtrace: #{e.backtrace.first(5).join('\n')}"
      raise e
    end

    # The task should be completed synchronously in test mode
    task.reload
    puts "Debug: Task status after handler.handle and reload: #{task.status}"
  end

  # Verify workflow execution results
  # @param task [Tasker::Task] The completed task
  # @param expected_status [String] Expected final status (default: 'complete')
  def verify_workflow_execution(task, expected_status: 'complete')
    expect(task.status).to eq(expected_status),
                           "Expected task status '#{expected_status}', got '#{task.status}'"

    # Verify all steps have expected statuses
    task.workflow_steps.each do |step|
      case expected_status
      when 'complete'
        expect(step.status).to eq('complete'),
                               "Step '#{step.name}' expected 'complete', got '#{step.status}'"
      when 'error'
        expect(%w[error complete]).to include(step.status),
                                      "Step '#{step.name}' has unexpected status '#{step.status}'"
      end
    end
  end

  # Get blog configuration file path
  # @param post_name [String] Blog post directory name
  # @param config_name [String] Configuration file name
  def blog_config_path(post_name, config_name)
    File.join(BLOG_FIXTURES_ROOT, post_name, 'config', config_name)
  end

  # Create sample test data for e-commerce examples
  def sample_ecommerce_context
    {
      customer_info: {
        id: 123,
        email: 'customer@example.com',
        tier: 'standard',
        name: 'John Doe'
      },
      cart_items: [
        {
          product_id: 1,
          quantity: 2,
          price: 29.99,
          name: 'Widget A'
        },
        {
          product_id: 2,
          quantity: 1,
          price: 49.99,
          name: 'Widget B'
        }
      ],
      payment_info: {
        method: 'credit_card',
        amount: 124.76,
        currency: 'USD',
        card_last_four: '1234',
        token: 'tok_visa_valid'
      },
      shipping_info: {
        address: '123 Main St',
        city: 'Anytown',
        state: 'NY',
        zip: '12345'
      }
    }
  end

  # Create sample test data for data pipeline examples
  def sample_analytics_context
    {
      date_range: {
        start_date: '2024-01-01',
        end_date: '2024-01-31'
      },
      metrics: %w[customer_lifetime_value product_performance user_engagement],
      output_format: 'json',
      notification_recipients: ['analytics@example.com']
    }
  end

  # Create sample test data for microservices examples
  def sample_registration_context
    {
      user_info: {
        email: 'newuser@example.com',
        name: 'Jane Smith',
        plan: 'pro'
      },
      billing_info: {
        payment_method: 'credit_card',
        billing_address: {
          street: '456 Oak Ave',
          city: 'Springfield',
          state: 'CA',
          zip: '90210'
        }
      },
      preferences: {
        marketing_emails: true,
        product_updates: true,
        newsletter: false
      }
    }
  end

  # Create sample test data for Post 04 payments refund examples
  def sample_payments_refund_context
    {
      'payment_id' => 'pay_123456789',
      'refund_amount' => 7500,
      'refund_reason' => 'customer_request',
      'partial_refund' => false,
      'correlation_id' => 'test_correlation_123'
    }
  end

  # Create sample test data for Post 04 customer success refund examples
  def sample_customer_success_refund_context
    {
      'ticket_id' => 'TICKET-98765',
      'customer_id' => 'CUST-54321',
      'refund_amount' => 12_000,
      'refund_reason' => 'Product defect reported by customer',
      'agent_notes' => 'Customer reported product malfunction after 2 weeks of use',
      'requires_approval' => true,
      'correlation_id' => 'cs_workflow_456',
      'customer_email' => 'customer@example.com',
      'payment_id' => 'pay_987654321'
    }
  end

  # Class methods for environment management
  class << self
    # Reset the blog test environment
    def reset_blog_environment!
      @loaded_files = []
      reset_mock_services!
      cleanup_blog_database_state!
      cleanup_blog_handler_registrations!
      # NOTE: We no longer cleanup blog namespaces since handlers are pre-registered
      # cleanup_blog_namespaces!
    end

    # Reset all mock services
    def reset_mock_services!
      # Reset old-style mock services (class-level reset)
      %w[
        MockPaymentService
        MockEmailService
        MockInventoryService
        MockDataWarehouseService
        MockDashboardService
        MockAnalyticsService
        MockMetricsService
        MockErrorReportingService
      ].each do |service_name|
        Object.const_get(service_name).reset! if Object.const_defined?(service_name)
      end

      # Reset global Tasker service instances
      Tasker.reset_metrics! if defined?(Tasker.reset_metrics!)
      Tasker.reset_error_reporter! if defined?(Tasker.reset_error_reporter!)

      # Reset new-style mock services (instance-level reset)
      %w[
        MockUserService
        MockBillingService
        MockPreferencesService
        MockNotificationService
      ].each do |service_name|
        if BlogExamples::MockServices.const_defined?(service_name)
          BlogExamples::MockServices.const_get(service_name).new.reset!
        end
      end
    end

    # Clean up blog-specific database state to prevent test leakage
    def cleanup_blog_database_state!
      # Remove blog-specific namespaces that might leak to other tests
      blog_namespaces = %w[blog_examples payments customer_success]

      blog_namespaces.each do |namespace_name|
        namespace = Tasker::TaskNamespace.find_by(name: namespace_name)
        next unless namespace

        # Clean up tasks in this namespace using the correct scope
        Tasker::Task.in_namespace(namespace_name).destroy_all

        # Get named tasks that need to be cleaned up
        named_tasks = Tasker::NamedTask.where(task_namespace: namespace)

        # Clean up join table records first to avoid foreign key constraint violations
        named_tasks.each do |named_task|
          Tasker::NamedTasksNamedStep.where(named_task: named_task).destroy_all
        end

        # Now clean up named tasks in this namespace
        named_tasks.destroy_all

        # Clean up the namespace itself
        namespace.destroy

        # Clean up any remaining orphaned tasks from blog tests
        Tasker::Task.in_namespace(namespace_name).destroy_all if Tasker::TaskNamespace.find_by(name: namespace_name)
      end
    end

    # Clean up blog-specific handler registrations to prevent test leakage
    def cleanup_blog_handler_registrations!
      factory = Tasker::HandlerFactory.instance

      # Remove blog handlers that interfere with core tests
      # Post 04 registers process_refund in payments namespace, which conflicts with core process_payment handlers
      cleanup_blog_handlers_in_namespace('payments', %w[process_refund])
      cleanup_blog_handlers_in_namespace('customer_success', %w[process_refund])

      # Clean up blog_examples namespace entirely if it exists
      factory.handler_classes.delete(:blog_examples)
      factory.namespaces.delete(:blog_examples)
    end

    # Clean up specific handlers in a namespace
    def cleanup_blog_handlers_in_namespace(namespace_name, handler_names)
      factory = Tasker::HandlerFactory.instance
      namespace_sym = namespace_name.to_sym

      # Only clean up if the namespace exists
      return unless factory.handler_classes.key?(namespace_sym)

      handler_names.each do |handler_name|
        handler_sym = handler_name.to_sym
        # Remove all versions of this handler
        factory.handler_classes[namespace_sym]&.delete(handler_sym)
      end

      # If namespace is now empty, remove it entirely
      return unless factory.handler_classes[namespace_sym] && factory.handler_classes[namespace_sym].empty?

      factory.handler_classes.delete(namespace_sym)
      factory.namespaces.delete(namespace_sym)
    end

    # Get list of loaded blog files
    def loaded_files
      @loaded_files ||= []
    end

    # Remove blog-specific namespaces from the handler factory
    def cleanup_blog_namespaces!
      factory = Tasker::HandlerFactory.instance

      # Remove the entire blog_examples namespace
      factory.handler_classes.delete(:blog_examples)

      # Remove blog_examples from the namespaces set
      factory.namespaces.delete(:blog_examples)
    end
  end

  private

  # Track loaded files for cleanup
  def track_loaded_file(file_path)
    BlogSpecHelpers.loaded_files << file_path
  end

  # Load blog code safely with error handling
  # @param post_name [String] The blog post directory name
  def load_blog_code_safely(post_name)
    case post_name
    when 'post_01_ecommerce_reliability'
      load_post_01_code
    when 'post_02_data_pipeline_resilience'
      load_post_02_code
    when 'post_03_microservices_coordination'
      load_post_03_code
    when 'post_04_team_scaling'
      load_post_04_code
    when 'post_05_production_observability'
      load_post_05_code
    else
      raise "Unknown blog post: #{post_name}"
    end
  rescue StandardError => e
    # If we can't load the blog code, skip the test with a clear message
    skip "Could not load blog code for #{post_name}: #{e.message}"
  end

  # Load Post 01 (E-commerce Reliability) code
  def load_post_01_code
    post = 'post_01_ecommerce_reliability'

    # Load models
    load_blog_code(post, 'models/product.rb')
    load_blog_code(post, 'models/order.rb')

    # Load step handlers
    load_step_handlers(post, %w[
                         validate_cart_handler
                         process_payment_handler
                         update_inventory_handler
                         create_order_handler
                         send_confirmation_handler
                       ])

    # Load task handler
    load_blog_code(post, 'task_handler/order_processing_handler.rb')
  end

  # Load Post 02 (Data Pipeline Resilience) code
  def load_post_02_code
    post = 'post_02_data_pipeline_resilience'

    # Load step handlers
    load_step_handlers(post, %w[
                         extract_orders_handler
                         extract_users_handler
                         extract_products_handler
                         transform_customer_metrics_handler
                         transform_product_metrics_handler
                         generate_insights_handler
                         update_dashboard_handler
                         send_notifications_handler
                       ])

    # Load task handler (ConfiguredTask automatically loads YAML and defines step templates)
    load_blog_code(post, 'task_handler/customer_analytics_handler.rb')

    # NOTE: Handler registration is now done at test suite startup to avoid threading issues
    # The handler is pre-registered in handler_registration_helpers.rb
  end

  # Load Post 03 (Microservices Coordination) code
  def load_post_03_code
    post = 'post_03_microservices_coordination'

    # Load concerns first
    load_blog_code(post, 'concerns/api_request_handling.rb')

    # Load step handlers (using framework base classes)
    load_step_handlers(post, %w[
                         create_user_account_handler
                         setup_billing_profile_handler
                         initialize_preferences_handler
                         send_welcome_sequence_handler
                         update_user_status_handler
                       ])

    # Load task handler (ConfiguredTask automatically loads YAML and defines step templates)
    load_blog_code(post, 'task_handler/user_registration_handler.rb')

    # NOTE: Handler registration is now done at test suite startup to avoid threading issues
    # The handler is pre-registered in handler_registration_helpers.rb
  end

  # Load Post 04 (Team Scaling) code
  def load_post_04_code
    post = 'post_04_team_scaling'

    # Load payments team step handlers
    load_blog_code(post, 'step_handlers/payments/validate_payment_eligibility_handler.rb')
    load_blog_code(post, 'step_handlers/payments/process_gateway_refund_handler.rb')
    load_blog_code(post, 'step_handlers/payments/update_payment_records_handler.rb')
    load_blog_code(post, 'step_handlers/payments/notify_customer_handler.rb')

    # Load customer success team step handlers
    load_blog_code(post, 'step_handlers/customer_success/validate_refund_request_handler.rb')
    load_blog_code(post, 'step_handlers/customer_success/check_refund_policy_handler.rb')
    load_blog_code(post, 'step_handlers/customer_success/get_manager_approval_handler.rb')
    load_blog_code(post, 'step_handlers/customer_success/execute_refund_workflow_handler.rb')
    load_blog_code(post, 'step_handlers/customer_success/update_ticket_status_handler.rb')

    # Load task handlers (ConfiguredTask automatically loads YAML and defines step templates)
    load_blog_code(post, 'task_handlers/payments_process_refund_handler.rb')
    load_blog_code(post, 'task_handlers/customer_success_process_refund_handler.rb')

    # NOTE: Handler registration is now done at test suite startup to avoid threading issues
    # The handler is pre-registered in handler_registration_helpers.rb
  end

  # Load Post 05 (Production Observability) code
  def load_post_05_code
    post = 'post_05_production_observability'

    # Load step handlers
    load_step_handlers(post, %w[
                         validate_cart_handler
                         process_payment_handler
                         update_inventory_handler
                         create_order_handler
                         send_confirmation_handler
                       ])

    # Load task handler (ConfiguredTask automatically loads YAML and defines step templates)
    load_blog_code(post, 'task_handlers/monitored_checkout_handler.rb')

    # Load event subscribers (for observability testing)
    load_blog_code(post, 'event_subscribers/business_metrics_subscriber.rb')
    load_blog_code(post, 'event_subscribers/performance_monitoring_subscriber.rb')

    # NOTE: Handler registration is now done at test suite startup to avoid threading issues
    # The handler is pre-registered in handler_registration_helpers.rb
  end
end

# Configure RSpec to include blog helpers
RSpec.configure do |config|
  config.include BlogSpecHelpers

  # Set up blog-specific test environment
  config.before(:suite) do
    # Ensure clean state for blog tests (mock services only)
    BlogSpecHelpers.reset_mock_services!
  end

  # Blog-specific test setup for tagged tests
  config.around(:each, type: :blog_example) do |example|
    # Reset mock services before each blog test
    BlogSpecHelpers.reset_mock_services!

    begin
      example.run
    ensure
      # Clean up mock services and database state after each blog test
      # NOTE: Don't clean up handler registrations since they're pre-registered at test suite startup
      # and cleaning them up would cause "handler not found" errors in subsequent tests
      BlogSpecHelpers.reset_mock_services!
      BlogSpecHelpers.cleanup_blog_database_state!
      # BlogSpecHelpers.cleanup_blog_handler_registrations! # Commented out to prevent handler cleanup
    end
  end

  # Global cleanup to ensure mock services don't leak to NON-BLOG tests
  config.before do |example|
    # Reset mock services for non-blog tests to ensure clean state
    unless example.file_path.include?('/blog/')
      BlogSpecHelpers.reset_mock_services!
      BlogSpecHelpers.cleanup_blog_database_state!
      # NOTE: Don't clean up handler registrations for non-blog tests either
      # since handlers_spec.rb now expects blog handlers to coexist
      # BlogSpecHelpers.cleanup_blog_handler_registrations! # Commented out
    end
  end

  # Final cleanup to ensure mock services don't leak to other tests
  config.after(:suite) do
    BlogSpecHelpers.reset_mock_services!
    BlogSpecHelpers.cleanup_blog_database_state!
    # NOTE: Don't cleanup handlers at suite end since they may be needed by other test files
    # BlogSpecHelpers.cleanup_blog_handler_registrations! # Commented out
  end
end
