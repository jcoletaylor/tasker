# Blog Example Validation Framework

This directory contains a comprehensive testing framework that validates all blog post code examples against Tasker Engine 0.1.0, ensuring every code sample works correctly and follows best practices.

## Overview

The blog validation framework ensures that developers following our blog series at https://docs.tasker.systems will have reliable, working code that demonstrates Tasker Engine best practices.

## Directory Structure

```
spec/blog/
├── support/
│   ├── blog_spec_helper.rb          # Core helper with fixture-based loading
│   ├── mock_services/               # Mock external services
│   │   ├── base_mock_service.rb     # Base class for all mocks
│   │   ├── payment_service.rb       # Mock payment processing
│   │   ├── email_service.rb         # Mock email delivery
│   │   └── inventory_service.rb     # Mock inventory management
│   ├── test_data/                   # Shared test data (future)
│   └── shared_examples/             # Reusable test patterns (future)
├── fixtures/                        # Blog post code fixtures
│   └── post_01_ecommerce_reliability/ # E-commerce example code
│       ├── step_handlers/           # Step handler implementations
│       ├── task_handler/            # Task handler implementation
│       ├── models/                  # Demo models
│       ├── config/                  # YAML configurations
│       └── demo/                    # Demo controllers and utilities
├── post_01_ecommerce_reliability/   # E-commerce workflow validation
│   └── integration/
│       └── order_processing_workflow_spec.rb
├── post_02_data_pipeline_resilience/ # Data pipeline validation (future)
├── post_03_microservices_coordination/ # Microservices validation (future)
└── README.md                        # This file
```

## Key Features

### Fixture-Based Code Loading
The framework loads blog post code from fixtures within the Tasker repository, ensuring tests work reliably in CI and across all environments:

```ruby
# Load blog example code from fixtures
load_blog_code('post_01_ecommerce_reliability', 'step_handlers/validate_cart_handler.rb')

# Load multiple step handlers
load_step_handlers('post_01_ecommerce_reliability', [
  'validate_cart_handler',
  'process_payment_handler',
  'update_inventory_handler'
])
```

### Mock Services
Comprehensive mock services simulate external dependencies:

```ruby
# Configure payment failure
MockPaymentService.stub_failure(:process_payment, MockPaymentService::PaymentError)

# Configure custom response
MockPaymentService.stub_response(:process_payment, {
  payment_id: 'pay_custom123',
  status: 'succeeded'
})

# Check call history
expect(MockPaymentService.called?(:process_payment)).to be true
expect(MockPaymentService.call_count(:process_payment)).to eq(3)
```

### Integration Testing
Complete workflow execution validation:

```ruby
# Create and execute workflow
task = create_test_task(
  name: 'order_processing',
  context: sample_ecommerce_context
)

execute_workflow(task)
verify_workflow_execution(task, expected_status: 'complete')
```

## Running Tests

### Run All Blog Validation Tests
```bash
bundle exec rspec spec/blog/
```

### Run Specific Post Tests
```bash
bundle exec rspec spec/blog/post_01_ecommerce_reliability/
```

### Run with Detailed Output
```bash
bundle exec rspec spec/blog/ --format documentation
```

## Test Categories

### Integration Tests
- **Location**: `post_XX_*/integration/`
- **Purpose**: End-to-end workflow validation
- **Scope**: Complete workflows with all steps and dependencies

### Step Handler Tests (Future)
- **Location**: `post_XX_*/step_handlers/`
- **Purpose**: Individual step validation
- **Scope**: Single step handlers with mocked dependencies

### Configuration Tests (Future)
- **Location**: `post_XX_*/configuration/`
- **Purpose**: YAML configuration validation
- **Scope**: Configuration file structure and content

## Blog Posts Coverage

### ✅ Post 01: E-commerce Reliability
- **Status**: Integration tests implemented
- **Coverage**: Complete order processing workflow
- **Files**: 13 Ruby files, 2 YAML configs
- **Tests**: Successful flow, error handling, configuration validation

### 🚧 Post 02: Data Pipeline Resilience
- **Status**: Structure created, tests pending
- **Coverage**: ETL workflows and analytics pipelines
- **Files**: 9 Ruby files, 1 YAML config

### 🚧 Post 03: Microservices Coordination
- **Status**: Structure created, tests pending
- **Coverage**: Circuit breaker patterns and service coordination
- **Files**: 8 Ruby files, 1 YAML config

## Mock Services Available

### MockPaymentService
Simulates payment processing with support for:
- Payment processing with fees calculation
- Payment refunds and status checks
- Payment method verification
- Configurable failures and delays

### MockEmailService
Simulates email delivery with support for:
- Confirmation emails with templates
- Welcome and notification emails
- Bulk email sending
- Delivery status tracking

### MockInventoryService
Simulates inventory management with support for:
- Availability checking
- Inventory reservations and commits
- Stock level updates
- Low stock alerts

## Adding New Tests

### For a New Blog Post
1. Create directory structure:
   ```bash
   mkdir -p spec/blog/post_XX_new_topic/{integration,step_handlers,configuration}
   ```

2. Create integration test:
   ```ruby
   require 'blog_spec_helper'

   RSpec.describe 'Post XX: New Topic', type: :blog_example do
     let(:blog_post) { 'post-XX-new-topic' }

     before(:each) do
       load_blog_code(blog_post, 'task_handler/main_handler.rb')
       # Load other required files...
     end

     it 'validates the workflow' do
       task = create_test_task(name: 'workflow_name', context: test_context)
       execute_workflow(task)
       verify_workflow_execution(task)
     end
   end
   ```

### For a New Mock Service
1. Create the service file in `spec/blog/support/mock_services/`:
   ```ruby
   require_relative 'base_mock_service'

   class MockNewService < BaseMockService
     def self.service_method(param:)
       instance = new
       instance.log_call(:service_method, { param: param })

       default_response = { result: 'success' }
       instance.handle_response(:service_method, default_response)
     end
   end
   ```

2. Add to the reset list in `blog_spec_helper.rb`:
   ```ruby
   def reset_mock_services!
     # Add 'MockNewService' to the list
   end
   ```

## Validation Criteria

### Code Quality
- ✅ Syntax validation (all Ruby code compiles)
- ✅ API compatibility (uses Tasker Engine 0.1.0 APIs)
- ✅ Style compliance (follows Tasker conventions)
- ✅ Error handling (proper exception handling)

### Functional Validation
- ✅ Workflow execution (complete workflows run successfully)
- ✅ Step dependencies (dependencies resolve correctly)
- ✅ State management (proper state transitions)
- ✅ Retry logic (intelligent retry behavior)

### Integration Validation
- ✅ Configuration loading (YAML configs load correctly)
- ✅ Handler registration (handlers register properly)
- ✅ External services (mock services work correctly)
- ⏳ Event publishing (events fire appropriately)
- ⏳ Database operations (proper database interactions)

## Contributing

When adding new blog posts or examples:

1. **Test First**: Create validation tests before publishing blog content
2. **Use Mocks**: Mock all external dependencies
3. **Real Code**: Tests should load actual blog post code, not copies
4. **Comprehensive**: Cover success cases, error cases, and edge cases
5. **Document**: Update this README with new coverage

## Status Legend
- ✅ **Complete**: Fully implemented and tested
- 🚧 **In Progress**: Structure created, implementation pending
- ⏳ **Planned**: Identified for future implementation
- ❌ **Blocked**: Waiting for dependencies or decisions

This validation framework ensures that every developer following our blog series will have success rather than frustration, building trust and adoption for Tasker Engine in the Rails community.
