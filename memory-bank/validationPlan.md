# Blog Example Validation Framework Plan

## Overview
Create a comprehensive testing framework in `spec/blog/` that validates all blog post code examples against Tasker Engine 1.0.0, ensuring every code sample works correctly and follows best practices.

## Directory Structure Plan

```
spec/
├── blog/
│   ├── support/
│   │   ├── blog_spec_helper.rb          # Blog-specific test helpers
│   │   ├── mock_services/               # Mock external services
│   │   │   ├── payment_service.rb       # Mock payment processing
│   │   │   ├── email_service.rb         # Mock email delivery
│   │   │   ├── inventory_service.rb     # Mock inventory management
│   │   │   ├── analytics_service.rb     # Mock analytics APIs
│   │   │   └── user_service.rb          # Mock user account APIs
│   │   ├── test_data/                   # Shared test data
│   │   │   ├── products.rb              # Sample product data
│   │   │   ├── orders.rb                # Sample order data
│   │   │   └── customers.rb             # Sample customer data
│   │   └── shared_examples/             # Reusable test patterns
│   │       ├── workflow_execution.rb    # Common workflow tests
│   │       ├── step_handler_behavior.rb # Step handler validation
│   │       └── configuration_validation.rb # YAML config tests
│   ├── post_01_ecommerce_reliability/
│   │   ├── integration/
│   │   │   └── order_processing_workflow_spec.rb
│   │   ├── step_handlers/
│   │   │   ├── validate_cart_handler_spec.rb
│   │   │   ├── process_payment_handler_spec.rb
│   │   │   ├── update_inventory_handler_spec.rb
│   │   │   ├── create_order_handler_spec.rb
│   │   │   └── send_confirmation_handler_spec.rb
│   │   ├── task_handler/
│   │   │   └── order_processing_handler_spec.rb
│   │   ├── models/
│   │   │   ├── order_spec.rb
│   │   │   └── product_spec.rb
│   │   └── configuration/
│   │       ├── order_processing_yaml_spec.rb
│   │       └── handler_configuration_spec.rb
│   ├── post_02_data_pipeline_resilience/
│   │   ├── integration/
│   │   │   └── customer_analytics_workflow_spec.rb
│   │   ├── step_handlers/
│   │   │   ├── extract_orders_handler_spec.rb
│   │   │   ├── extract_products_handler_spec.rb
│   │   │   ├── extract_users_handler_spec.rb
│   │   │   ├── transform_customer_metrics_handler_spec.rb
│   │   │   ├── transform_product_metrics_handler_spec.rb
│   │   │   ├── generate_insights_handler_spec.rb
│   │   │   ├── update_dashboard_handler_spec.rb
│   │   │   └── send_notifications_handler_spec.rb
│   │   ├── task_handler/
│   │   │   └── customer_analytics_handler_spec.rb
│   │   └── configuration/
│   │       └── customer_analytics_yaml_spec.rb
│   ├── post_03_microservices_coordination/
│   │   ├── integration/
│   │   │   └── user_registration_workflow_spec.rb
│   │   ├── step_handlers/
│   │   │   ├── api_base_handler_spec.rb
│   │   │   ├── create_user_account_handler_spec.rb
│   │   │   ├── setup_billing_profile_handler_spec.rb
│   │   │   ├── initialize_preferences_handler_spec.rb
│   │   │   ├── send_welcome_sequence_handler_spec.rb
│   │   │   └── update_user_status_handler_spec.rb
│   │   ├── concerns/
│   │   │   └── circuit_breaker_pattern_spec.rb
│   │   ├── task_handler/
│   │   │   └── user_registration_handler_spec.rb
│   │   └── configuration/
│   │       └── user_registration_yaml_spec.rb
│   └── README.md                        # Blog validation documentation
```

## Implementation Strategy

### Phase 1: Foundation Setup (Week 1)

#### 1.1 Create Basic Structure
```bash
mkdir -p spec/blog/support/{mock_services,test_data,shared_examples}
mkdir -p spec/blog/post_01_ecommerce_reliability/{integration,step_handlers,task_handler,models,configuration}
```

#### 1.2 Blog Spec Helper
Create `spec/blog/support/blog_spec_helper.rb`:
```ruby
# Shared helper for blog example validation
require 'rails_helper'

RSpec.configure do |config|
  config.include BlogSpecHelpers
end

module BlogSpecHelpers
  # Load blog example code dynamically
  def load_blog_code(post_name, file_path)
    blog_root = "/Users/petetaylor/projects/tasker-blog/blog/posts"
    full_path = File.join(blog_root, post_name, "code-examples", file_path)
    require full_path
  end

  # Create test task with realistic context
  def create_test_task(name:, context:, namespace: 'blog_examples')
    task_request = Tasker::Types::TaskRequest.new(
      name: name,
      namespace: namespace,
      context: context
    )

    handler = Tasker::HandlerFactory.instance.get(name, namespace_name: namespace)
    handler.initialize_task!(task_request)
  end

  # Validate YAML configuration
  def validate_yaml_config(config_path)
    config = YAML.load_file(config_path)
    expect(config).to include('name', 'step_templates')
    expect(config['step_templates']).to be_an(Array)
    config
  end
end
```

#### 1.3 Mock Services Framework
Create base mock service pattern in `spec/blog/support/mock_services/`:

```ruby
# Base mock service
class MockService
  def self.reset!
    @call_log = []
    @responses = {}
    @failures = {}
  end

  def self.stub_response(method, response)
    @responses ||= {}
    @responses[method] = response
  end

  def self.stub_failure(method, error_class = StandardError)
    @failures ||= {}
    @failures[method] = error_class
  end

  def self.call_log
    @call_log ||= []
  end

  private

  def log_call(method, args = {})
    self.class.call_log << { method: method, args: args, timestamp: Time.current }
  end

  def handle_response(method, default_response = {})
    if self.class.instance_variable_get(:@failures)&.key?(method)
      raise self.class.instance_variable_get(:@failures)[method]
    end

    self.class.instance_variable_get(:@responses)&.fetch(method, default_response)
  end
end
```

### Phase 2: Post 01 Validation (Week 2)

#### 2.1 Integration Test for Complete Workflow
Create `spec/blog/post_01_ecommerce_reliability/integration/order_processing_workflow_spec.rb`:

```ruby
require 'blog_spec_helper'

RSpec.describe 'Post 01: E-commerce Order Processing Workflow' do
  let(:blog_post) { 'post-01-ecommerce-reliability' }

  before(:each) do
    # Load all blog example code
    load_blog_code(blog_post, 'models/product.rb')
    load_blog_code(blog_post, 'models/order.rb')
    load_blog_code(blog_post, 'task_handler/order_processing_handler.rb')

    # Load step handlers
    %w[
      validate_cart_handler
      process_payment_handler
      update_inventory_handler
      create_order_handler
      send_confirmation_handler
    ].each do |handler|
      load_blog_code(blog_post, "step_handlers/#{handler}.rb")
    end

    # Reset mock services
    MockPaymentService.reset!
    MockEmailService.reset!
    MockInventoryService.reset!
  end

  describe 'successful checkout flow' do
    it 'processes a complete order successfully' do
      # Test the exact scenario from the blog post
      task = create_test_task(
        name: 'order_processing',
        context: {
          customer_info: {
            id: 123,
            email: 'customer@example.com',
            tier: 'standard'
          },
          cart_items: [
            { product_id: 1, quantity: 2, price: 29.99 },
            { product_id: 2, quantity: 1, price: 49.99 }
          ],
          payment_info: {
            method: 'credit_card',
            amount: 109.97,
            currency: 'USD'
          }
        }
      )

      expect(task.status).to eq('pending')

      # Execute workflow
      Tasker::Orchestration::WorkflowCoordinator.new.process_task(task)

      # Verify final state
      task.reload
      expect(task.status).to eq('complete')

      # Verify all steps completed
      task.workflow_steps.each do |step|
        expect(step.status).to eq('complete')
      end

      # Verify side effects
      expect(MockPaymentService.call_log).to include(
        hash_including(method: :process_payment, args: hash_including(amount: 109.97))
      )

      expect(MockEmailService.call_log).to include(
        hash_including(method: :send_confirmation)
      )
    end
  end

  describe 'error handling and recovery' do
    it 'retries payment failures with exponential backoff' do
      # Simulate payment service failure
      MockPaymentService.stub_failure(:process_payment, PaymentError)

      task = create_test_task(
        name: 'order_processing',
        context: valid_order_context
      )

      # Execute workflow
      Tasker::Orchestration::WorkflowCoordinator.new.process_task(task)

      # Verify retry behavior
      payment_step = task.workflow_steps.find { |s| s.name == 'process_payment' }
      expect(payment_step.status).to eq('error')
      expect(payment_step.attempts).to be > 1
    end
  end
end
```

#### 2.2 Individual Step Handler Tests
Create focused tests for each step handler, validating:
- Input/output contracts
- Error handling
- Retry behavior
- Business logic correctness

#### 2.3 Configuration Validation
Test YAML configurations for:
- Syntax correctness
- Required fields presence
- Step dependency validation
- Handler class references

### Phase 3: Mock Service Implementation (Week 3)

#### 3.1 Payment Service Mock
```ruby
class MockPaymentService < MockService
  def self.process_payment(amount:, method:, **options)
    instance = new
    instance.log_call(:process_payment, { amount: amount, method: method })

    response = instance.handle_response(:process_payment, {
      payment_id: "pay_#{SecureRandom.hex(8)}",
      status: 'succeeded',
      amount_charged: amount,
      payment_method_type: method
    })

    response
  end
end
```

#### 3.2 Email Service Mock
```ruby
class MockEmailService < MockService
  def self.send_confirmation(to:, template:, **options)
    instance = new
    instance.log_call(:send_confirmation, { to: to, template: template })

    response = instance.handle_response(:send_confirmation, {
      message_id: "msg_#{SecureRandom.hex(8)}",
      status: 'sent',
      recipient: to
    })

    response
  end
end
```

### Phase 4: Advanced Validation (Week 4)

#### 4.1 Performance Testing
- Validate workflow execution times
- Test concurrent step execution
- Memory usage validation

#### 4.2 Error Scenario Testing
- Network failures
- Service timeouts
- Database errors
- Invalid input handling

#### 4.3 Configuration Edge Cases
- Missing required fields
- Invalid step dependencies
- Circular dependencies
- Non-existent handler classes

## Validation Criteria

### Code Quality Checks
1. **Syntax Validation**: All Ruby code must be syntactically correct
2. **Style Compliance**: Code follows Tasker Engine conventions
3. **API Compatibility**: Uses only Tasker Engine 1.0.0 public APIs
4. **Error Handling**: Proper exception handling and recovery
5. **Documentation**: Code matches blog post descriptions

### Functional Validation
1. **Workflow Execution**: Complete workflows execute successfully
2. **Step Dependencies**: Dependencies resolve correctly
3. **State Management**: Proper state transitions
4. **Retry Logic**: Intelligent retry behavior
5. **Data Flow**: Correct data passing between steps

### Integration Validation
1. **Configuration Loading**: YAML configs load correctly
2. **Handler Registration**: Task and step handlers register properly
3. **Event Publishing**: Events fire at appropriate times
4. **Database Operations**: Proper database interactions
5. **External Service Integration**: Mock services work correctly

## Success Metrics

### Immediate Goals
- **100% Syntax Validation**: All blog code compiles without errors
- **Core Workflow Success**: Post 01 complete workflow executes successfully
- **Basic Error Handling**: Retry and failure scenarios work correctly

### Medium-term Goals
- **All Posts 01-03 Validated**: Complete validation of primary blog posts
- **Performance Benchmarks**: Establish baseline performance characteristics
- **CI Integration**: Automated validation in continuous integration

### Long-term Goals
- **Zero Blog Bugs**: No functional errors in any blog examples
- **Best Practice Compliance**: All examples follow Tasker Engine best practices
- **Community Confidence**: Developers trust blog examples to work correctly

This validation framework ensures that every developer following the blog series will have success rather than frustration, building trust and adoption for Tasker Engine in the Rails community.
