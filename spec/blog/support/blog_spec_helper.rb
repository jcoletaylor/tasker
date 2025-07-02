# Blog Example Validation Helper
# Provides utilities for testing blog post code examples against Tasker Engine
require 'rails_helper'

module BlogSpecHelpers
  # Path to the blog fixtures within the Tasker repository
  BLOG_FIXTURES_ROOT = File.join(File.dirname(__FILE__), '..', 'fixtures').freeze

  # Load blog example code dynamically from fixtures
  # @param post_name [String] The blog post directory name (e.g., 'post_01_ecommerce_reliability')
  # @param file_path [String] The relative path within the fixtures (e.g., 'step_handlers/validate_cart_handler.rb')
  def load_blog_code(post_name, file_path)
    full_path = File.join(BLOG_FIXTURES_ROOT, post_name, file_path)

    unless File.exist?(full_path)
      raise "Blog code file not found: #{full_path}"
    end

    # Load the file and track it for cleanup
    require full_path
    track_loaded_file(full_path)
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
  def create_test_task(name:, context:, namespace: 'blog_examples')
    task_request = Tasker::Types::TaskRequest.new(
      name: name,
      namespace: namespace,
      context: context
    )

    # Get the handler and initialize the task
    handler = Tasker::HandlerFactory.instance.get(name, namespace_name: namespace)
    task = handler.initialize_task!(task_request)

    # Ensure task is persisted for testing
    task.save! if task.respond_to?(:save!)
    task
  end

  # Validate YAML configuration file
  # @param config_path [String] Path to the YAML configuration file
  # @return [Hash] Parsed configuration
  def validate_yaml_config(config_path)
    unless File.exist?(config_path)
      raise "Configuration file not found: #{config_path}"
    end

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
    # Start workflow execution
    coordinator = Tasker::Orchestration::WorkflowCoordinator.new
    coordinator.process_task(task)

    # Wait for completion or timeout
    start_time = Time.current
    while task.status == 'pending' && (Time.current - start_time) < timeout
      sleep(0.1)
      task.reload
    end

    if task.status == 'pending'
      raise "Workflow execution timed out after #{timeout} seconds"
    end

    task
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
        expect(['error', 'complete']).to include(step.status),
               "Step '#{step.name}' has unexpected status '#{step.status}'"
      end
    end
  end

  # Get blog configuration file path
  # @param post_name [String] Blog post directory name
  # @param config_name [String] Configuration file name
  def blog_config_path(post_name, config_name)
    File.join(BLOG_FIXTURES_ROOT, post_name, "config", config_name)
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
        amount: 109.97,
        currency: 'USD',
        card_last_four: '1234'
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
      metrics: ['customer_lifetime_value', 'product_performance', 'user_engagement'],
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
    end

    # Reset all mock services
    def reset_mock_services!
      # Reset each mock service if it's defined
      [
        'MockPaymentService',
        'MockEmailService',
        'MockInventoryService',
        'MockAnalyticsService',
        'MockUserService',
        'MockBillingService',
        'MockNotificationService'
      ].each do |service_name|
        if Object.const_defined?(service_name)
          Object.const_get(service_name).reset!
        end
      end
    end

    # Get list of loaded blog files
    def loaded_files
      @loaded_files ||= []
    end
  end

  private

  # Track loaded files for cleanup
  def track_loaded_file(file_path)
    BlogSpecHelpers.loaded_files << file_path
  end
end

# Configure RSpec to include blog helpers
RSpec.configure do |config|
  config.include BlogSpecHelpers

  # Set up blog-specific test environment
  config.before(:suite) do
    # Ensure clean state for blog tests
    BlogSpecHelpers.reset_blog_environment!
  end

  config.before(:each, type: :blog_example) do
    # Reset mock services before each blog test
    BlogSpecHelpers.reset_mock_services!
  end
end
