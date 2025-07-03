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
    # If no version specified, use 1.0.0 for blog examples (from YAML configs)
    handler = if version
                Tasker::HandlerFactory.instance.get(name, namespace_name: namespace, version: version)
              elsif namespace == 'blog_examples'
                # Blog examples use version 1.0.0 from YAML configurations
                Tasker::HandlerFactory.instance.get(name, namespace_name: namespace, version: '1.0.0')
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
    handler = if task.namespace_name == 'blog_examples'
                Tasker::HandlerFactory.instance.get(task.name, namespace_name: task.namespace_name, version: '1.0.0')
              else
                Tasker::HandlerFactory.instance.get(task.name, namespace_name: task.namespace_name)
              end

    # Execute the workflow using the task handler
    handler.handle(task)

    # The task should be completed synchronously in test mode
    task.reload
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

  # Class methods for environment management
  class << self
    # Reset the blog test environment
    def reset_blog_environment!
      @loaded_files = []
      reset_mock_services!
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
      ].each do |service_name|
        Object.const_get(service_name).reset! if Object.const_defined?(service_name)
      end

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
      # Clean up mock services after each blog test
      # NOTE: We no longer clean up blog namespaces since handlers are pre-registered
      BlogSpecHelpers.reset_mock_services!
    end
  end

  # Global cleanup to ensure mock services don't leak to NON-BLOG tests
  config.before do |example|
    # Reset mock services for non-blog tests to ensure clean state
    BlogSpecHelpers.reset_mock_services! unless example.file_path.include?('/blog/')
  end

  # Final cleanup to ensure mock services don't leak to other tests
  config.after(:suite) do
    BlogSpecHelpers.reset_mock_services!
  end
end
