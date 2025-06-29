# Quick Start Guide: Your First Tasker Workflow

## Goal: Working Workflow in 5 Minutes

This guide will get you from zero to a working Tasker application with complete workflows in **5 minutes**. We'll use our automated demo application builder to create a full-featured Rails app with real-world workflow examples, then explore how to customize and extend them.

**🚀 New in Tasker 2.5.0**: This guide leverages our enterprise-grade demo application builder with:
- **Automated Setup**: One-command installation with complete Rails application
- **Real-World Examples**: E-commerce, inventory, and customer management workflows
- **Performance Optimization**: Dynamic concurrency with configurable execution settings
- **Full Observability**: OpenTelemetry tracing and Prometheus metrics integration
- **Production Ready**: Complete with Redis, Sidekiq, and comprehensive documentation

*Why this approach?* Instead of manual setup, we'll use proven patterns from our demo builder that create production-ready applications instantly.

## Prerequisites (1 minute)

Ensure you have:
- **Ruby 3.2+** with bundler
- **PostgreSQL** running locally
- **Basic terminal access**
- **Optional**: Redis for caching (will be configured automatically)

## Installation & Setup (2 minutes)

### Option 1: Automated Demo Application (Recommended)

Create a complete Tasker application with real-world workflows instantly:

```bash
# Interactive setup with full observability stack
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/scripts/install-tasker-app.sh | bash

# Or specify your preferences
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/scripts/install-tasker-app.sh | bash -s -- \
  --app-name my-tasker-demo \
  --tasks ecommerce,inventory,customer \
  --observability \
  --non-interactive
```

This creates a complete Rails application with:
- ✅ **Tasker gem** installed and configured
- ✅ **All 21 migrations** executed with database views/functions
- ✅ **3 complete workflows** (e-commerce, inventory, customer management)
- ✅ **Redis & Sidekiq** configured for background processing
- ✅ **OpenTelemetry** tracing and **Prometheus** metrics
- ✅ **Performance configuration** with execution tuning examples

**Skip to "Exploring Your Workflows"** below to start using your new application!

### Option 2: Manual Installation (Existing Rails App)

If you have an existing Rails application:

```bash
# Add to Gemfile
echo 'gem "tasker", git: "https://github.com/tasker-systems/tasker.git", tag: "v2.5.0"' >> Gemfile

# Install and setup
bundle install
bundle exec rails tasker:install:migrations
bundle exec rails tasker:install:database_objects  # Critical step!
bundle exec rails db:migrate
bundle exec rails tasker:setup

# Mount the engine
echo 'mount Tasker::Engine, at: "/tasker"' >> config/routes.rb
```

## Exploring Your Workflows (2 minutes)

If you used the automated demo application builder, you now have a complete Rails application with three working workflows. Let's explore them!

### Start Your Application

```bash
cd your-app-name  # Use the name you chose during installation

# Start the services
bundle exec redis-server &          # Background Redis
bundle exec sidekiq &               # Background Sidekiq
bundle exec rails server            # Rails application
```

### Explore the Demo Workflows

Your application includes three complete, production-ready workflows:

#### 1. **E-commerce Order Processing**
- **File**: `app/tasks/ecommerce/order_processing_handler.rb`
- **Steps**: Validate order → Process payment → Update inventory → Send confirmation
- **Features**: Retry logic, error handling, real API integration with DummyJSON

#### 2. **Inventory Management**
- **File**: `app/tasks/inventory/stock_management_handler.rb`
- **Steps**: Check stock levels → Update quantities → Generate reports → Send alerts
- **Features**: Conditional logic, parallel processing, data aggregation

#### 3. **Customer Management**
- **File**: `app/tasks/customer/profile_management_handler.rb`
- **Steps**: Validate customer → Update profile → Sync external systems → Send notifications
- **Features**: External API calls, data transformation, notification patterns

### Test the Workflows

Access your application's interfaces:

```bash
# Visit these URLs in your browser:
open http://localhost:3000/tasker/graphql     # GraphQL API interface
open http://localhost:3000/tasker/api-docs    # REST API documentation
open http://localhost:3000/tasker/metrics     # Prometheus metrics endpoint
```

#### Create and Execute a Task via GraphQL

1. **Open GraphQL Interface**: Navigate to `http://localhost:3000/tasker/graphql`

2. **Create an E-commerce Order Task**:
```graphql
mutation {
  createTask(input: {
    taskName: "ecommerce_order_processing"
    context: {
      order_id: 123
      customer_id: 456
      items: [
        { product_id: 1, quantity: 2, price: 29.99 }
        { product_id: 2, quantity: 1, price: 49.99 }
      ]
      payment_method: "credit_card"
    }
  }) {
    task {
      taskId
      currentState
      workflowSteps {
        name
        currentState
      }
    }
  }
}
```

3. **Monitor Task Progress**:
```graphql
query {
  task(taskId: "your-task-id-here") {
    taskId
    currentState
    workflowSteps {
      name
      currentState
      results
      attempts
    }
  }
}
```

## Performance Configuration (1 minute)

Your demo application includes comprehensive execution configuration examples. Explore the performance tuning options:

### View Current Configuration

```ruby
# In Rails console
rails console

# Check current execution settings
config = Tasker.configuration.execution
puts "Min concurrent steps: #{config.min_concurrent_steps}"
puts "Max concurrent steps: #{config.max_concurrent_steps_limit}"
puts "Concurrency cache duration: #{config.concurrency_cache_duration} seconds"
```

### Environment-Specific Tuning

Your application includes configuration examples in:
- **`config/initializers/tasker.rb`**: Main configuration with execution settings
- **`config/execution_tuning_examples.rb`**: 7 environment-specific examples:
  - Development: Conservative settings (2-6 concurrent steps)
  - Production: High-performance (5-25 concurrent steps)
  - High-Performance: Maximum throughput (10-50 concurrent steps)
  - API-Heavy: Optimized for external APIs (3-8 concurrent steps)
  - Testing: Minimal concurrency for reliability (1-3 concurrent steps)

### Monitor Performance

```bash
# View metrics in your browser
open http://localhost:3000/tasker/metrics

# Check system health
curl http://localhost:3000/tasker/health/status | jq
```

## Creating Custom Workflows

Want to create your own workflow? Use our proven patterns:

### 1. Generate New Workflow Structure

```bash
# Generate a new task handler
rails generate tasker:task_handler WelcomeHandler --module_namespace WelcomeUser

# This creates:
# - app/tasks/welcome_user/welcome_handler.rb (task handler class)
# - config/tasker/tasks/welcome_user/welcome_handler.yaml (workflow configuration)
# - spec/tasks/welcome_user/welcome_handler_spec.rb (test file)
```

### 2. Configure Your Workflow

Edit `config/tasker/tasks/welcome_user/welcome_handler.yaml`:

```yaml
---
name: welcome_user
module_namespace: WelcomeUser
task_handler_class: WelcomeHandler

schema:
  type: object
  required:
    - user_id
  properties:
    user_id:
      type: integer

step_templates:
  - name: validate_user
    description: Ensure user exists and is valid for welcome email
    handler_class: WelcomeUser::StepHandler::ValidateUserHandler

  - name: generate_content
    description: Generate personalized welcome email content
    depends_on_step: validate_user
    handler_class: WelcomeUser::StepHandler::GenerateContentHandler

  - name: send_email
    description: Send the welcome email to the user
    depends_on_step: generate_content
    handler_class: WelcomeUser::StepHandler::SendEmailHandler
    default_retryable: true
    default_retry_limit: 3
