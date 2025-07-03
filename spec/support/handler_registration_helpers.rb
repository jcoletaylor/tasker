# typed: false
# frozen_string_literal: true

# Helper module for safe handler registration in tests
#
# This module provides utilities for registering handlers in tests without
# causing duplicate registration errors. It's designed to work with the
# modernized HandlerFactory that enforces unique registrations.
module HandlerRegistrationHelpers
  # Register a handler, using replace: true if it already exists
  #
  # @param name [String, Symbol] Handler name
  # @param handler_class [Class, String] Handler class
  # @param options [Hash] Registration options
  # @return [void]
  def safe_register_handler(name, handler_class, **options)
    # Skip registration for auto-registering handlers in test environment
    # These are already registered and don't need to be registered again
    return if AUTO_REGISTERING_HANDLERS.include?(name.to_s)

    # Ensure replace: true is set to avoid duplicate registration errors
    registration_options = options.merge(replace: true)

    begin
      Tasker::HandlerFactory.instance.register(
        name,
        handler_class,
        **registration_options
      )
    rescue StandardError => e
      Rails.logger.error { "Failed to register handler #{name}: #{e.message}" }
      raise
    end
  end

  # Check if a handler is already registered
  #
  # @param name [String, Symbol] Handler name
  # @param namespace_name [Symbol] Namespace name
  # @param version [String] Version
  # @return [Boolean] True if handler exists
  def handler_exists?(name, namespace_name = :default, version = '0.1.0')
    factory = Tasker::HandlerFactory.instance
    namespace_name = namespace_name.to_sym
    name_sym = name.to_sym

    factory.handler_classes.dig(namespace_name, name_sym, version).present?
  end

  # Register multiple handlers safely
  #
  # @param handlers [Hash] Hash of name => handler_class pairs
  # @param options [Hash] Common options for all registrations
  # @return [void]
  def safe_register_handlers(handlers, **options)
    handlers.each do |name, handler_class|
      safe_register_handler(name, handler_class, **options)
    end
  end

  # Register the common workflow task handlers used in tests
  #
  # @param options [Hash] Registration options
  # @return [void]
  def register_workflow_test_handlers(**)
    workflow_handlers = {
      'linear_workflow_task' => LinearWorkflowTask,
      'diamond_workflow_task' => DiamondWorkflowTask,
      'parallel_merge_workflow_task' => ParallelMergeWorkflowTask,
      'tree_workflow_task' => TreeWorkflowTask,
      'mixed_workflow_task' => MixedWorkflowTask
    }

    safe_register_handlers(workflow_handlers, **)
  end

  # Register the common test task handlers
  #
  # @param options [Hash] Registration options
  # @return [void]
  def register_basic_test_handlers(**)
    basic_handlers = {
      'dummy_task' => DummyTask,
      'dummy_api_task' => DummyApiTask,
      'configurable_failure_task' => ConfigurableFailureTask
    }

    safe_register_handlers(basic_handlers, **)
  end

  # Register all blog task handlers used in blog examples
  #
  # This method pre-registers all blog handlers at test suite startup to avoid
  # threading issues with concurrent handler registration during test execution.
  #
  # @param options [Hash] Registration options
  # @return [void]
  def register_blog_test_handlers(**options)
    # Ensure blog code is loaded before registering handlers
    load_all_blog_code_safely

    # Register blog task handlers in the blog_examples namespace
    blog_handlers = {
      'order_processing' => 'BlogExamples::Post01::OrderProcessingHandler',
      'customer_analytics' => 'BlogExamples::Post02::CustomerAnalyticsHandler',
      'user_registration' => 'BlogExamples::Post03::UserRegistrationHandler'
    }

    blog_options = {
      namespace_name: 'blog_examples',
      version: '1.0.0',
      replace: true
    }.merge(options)

    blog_handlers.each do |name, handler_class_name|
      # Convert string class name to actual class
      handler_class = handler_class_name.constantize
      safe_register_handler(name, handler_class, **blog_options)
    rescue NameError => e
      Rails.logger.warn { "Could not register blog handler #{name}: #{e.message}" }
    rescue StandardError => e
      Rails.logger.error { "Error registering blog handler #{name}: #{e.class} - #{e.message}" }
    end
  end

  # Override factory.register method calls to use safe registration
  #
  # This method can be used to wrap existing test registration patterns
  #
  # @param factory [Object] Handler factory instance
  # @param name [String, Symbol] Handler name
  # @param handler_class [Class, String] Handler class
  # @param options [Hash] Registration options
  # @return [void]
  def safe_factory_register(_factory, name, handler_class, **)
    safe_register_handler(name, handler_class, **)
  end

  # Unregister handlers that were registered during test
  #
  # @param handler_names [Array<String>] Names of handlers to unregister
  # @param options [Hash] Unregistration options
  # @return [void]
  def unregister_test_handlers(handler_names, **options)
    factory = Tasker::HandlerFactory.instance
    namespace_name = (options[:namespace_name] || :default).to_sym
    version = options[:version] || '0.1.0'

    handler_names.each do |name|
      name_sym = name.to_sym
      factory.handler_classes[namespace_name]&.dig(name_sym)&.delete(version)
    end
  end

  private

  # Load all blog code safely for handler registration
  #
  # This method loads all blog post code required for handler registration
  # while handling any loading errors gracefully.
  #
  # @return [void]
  def load_all_blog_code_safely
    blog_fixtures_root = File.join(File.dirname(__FILE__), '..', 'blog', 'fixtures')

    # Load Post 01 code
    begin
      load_blog_post_code('post_01_ecommerce_reliability', blog_fixtures_root)
    rescue StandardError => e
      Rails.logger.warn { "Could not load Post 01 blog code: #{e.message}" }
    end

    # Load Post 02 code
    begin
      load_blog_post_code('post_02_data_pipeline_resilience', blog_fixtures_root)
    rescue StandardError => e
      Rails.logger.warn { "Could not load Post 02 blog code: #{e.message}" }
    end

    # Load Post 03 code
    begin
      load_blog_post_code('post_03_microservices_coordination', blog_fixtures_root)
    rescue StandardError => e
      Rails.logger.warn { "Could not load Post 03 blog code: #{e.message}" }
    end
  end

  # Load blog post code for a specific post
  #
  # @param post_name [String] The blog post directory name
  # @param blog_fixtures_root [String] Root path to blog fixtures
  # @return [void]
  def load_blog_post_code(post_name, blog_fixtures_root)
    case post_name
    when 'post_01_ecommerce_reliability'
      load_post_01_code(blog_fixtures_root)
    when 'post_02_data_pipeline_resilience'
      load_post_02_code(blog_fixtures_root)
    when 'post_03_microservices_coordination'
      load_post_03_code(blog_fixtures_root)
    end
  end

  # Load Post 01 code
  def load_post_01_code(blog_fixtures_root)
    post_path = File.join(blog_fixtures_root, 'post_01_ecommerce_reliability')

    # Load models
    require File.join(post_path, 'models', 'product.rb')
    require File.join(post_path, 'models', 'order.rb')

    # Load step handlers
    %w[
      validate_cart_handler
      process_payment_handler
      update_inventory_handler
      create_order_handler
      send_confirmation_handler
    ].each do |handler_name|
      require File.join(post_path, 'step_handlers', "#{handler_name}.rb")
    end

    # Load task handler
    require File.join(post_path, 'task_handler', 'order_processing_handler.rb')
  end

  # Load Post 02 code
  def load_post_02_code(blog_fixtures_root)
    post_path = File.join(blog_fixtures_root, 'post_02_data_pipeline_resilience')

    # Load step handlers
    %w[
      extract_orders_handler
      extract_users_handler
      extract_products_handler
      transform_customer_metrics_handler
      transform_product_metrics_handler
      generate_insights_handler
      update_dashboard_handler
      send_notifications_handler
    ].each do |handler_name|
      require File.join(post_path, 'step_handlers', "#{handler_name}.rb")
    end

    # Load task handler
    require File.join(post_path, 'task_handler', 'customer_analytics_handler.rb')
  end

  # Load Post 03 code
  def load_post_03_code(blog_fixtures_root)
    post_path = File.join(blog_fixtures_root, 'post_03_microservices_coordination')

    # Load concerns first
    require File.join(post_path, 'concerns', 'api_request_handling.rb')

    # Load step handlers
    %w[
      create_user_account_handler
      setup_billing_profile_handler
      initialize_preferences_handler
      send_welcome_sequence_handler
      update_user_status_handler
    ].each do |handler_name|
      require File.join(post_path, 'step_handlers', "#{handler_name}.rb")
    end

    # Load task handler
    require File.join(post_path, 'task_handler', 'user_registration_handler.rb')
  end
end

# Auto-registering handlers that should not be registered again in tests
# This includes main test handlers that auto-register themselves
# Blog handlers are NOT included here since they need manual registration
AUTO_REGISTERING_HANDLERS = %w[
  dummy_task
  dummy_api_task
  configurable_failure_task
  linear_workflow_task
  diamond_workflow_task
  parallel_merge_workflow_task
  tree_workflow_task
  mixed_workflow_task
].freeze

# Check if a handler auto-registers itself
#
# @param name [String, Symbol] Handler name
# @return [Boolean] True if handler auto-registers
def auto_registering_handler?(name)
  AUTO_REGISTERING_HANDLERS.include?(name.to_s)
end

# Include in RSpec configuration
RSpec.configure do |config|
  config.include HandlerRegistrationHelpers

  # Pre-register all blog handlers at test suite startup to avoid threading issues
  config.before(:suite) do
    # Register blog handlers in a single-threaded context
    extend HandlerRegistrationHelpers
    register_blog_test_handlers
  end
end
