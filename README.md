[![CI](https://github.com/jcoletaylor/tasker/actions/workflows/main.yml/badge.svg)](https://github.com/jcoletaylor/tasker/actions/workflows/main.yml)
![GitHub](https://img.shields.io/github/license/jcoletaylor/tasker)
![GitHub release (latest SemVer)](https://img.shields.io/github/v/release/jcoletaylor/tasker?color=blue&sort=semver)

# Tasker: Production-Ready Workflow Orchestration Engine

🎉 **MAJOR BREAKTHROUGH**: Critical production bug **SUCCESSFULLY FIXED**! Tasker is now a **fully functional, production-ready** workflow orchestration engine designed to make developing complex, resilient multi-step tasks easy to reason about.

## 🎯 Current Status: PRODUCTION READY ✅
- ✅ **Critical TaskFinalizer Bug Fixed** - Proper retry orchestration now working
- ✅ **All Workflow Patterns Validated** - Linear, diamond, tree, parallel merge all tested
- ✅ **Complete Test Coverage** - 24/24 production workflow tests passing
- ✅ **High-Performance SQL Functions** - 4x performance improvements achieved
- ✅ **Resilient Architecture** - Exponential backoff and failure recovery working

## Getting Started with Tasker

This guide will walk you through the fundamentals of using Tasker to build complex, production-ready task workflows with automatic retries, intelligent error handling, and sophisticated concurrency patterns.

## Table of Contents

- [Tasker: Production-Ready Workflow Orchestration Engine](#tasker-production-ready-workflow-orchestration-engine)
  - [🎯 Current Status: PRODUCTION READY ✅](#-current-status-production-ready-)
  - [Getting Started with Tasker](#getting-started-with-tasker)
  - [Table of Contents](#table-of-contents)
  - [Introduction](#introduction)
    - [🚀 Core Capabilities](#-core-capabilities)
  - [Installation](#installation)
  - [Core Concepts](#core-concepts)
  - [Creating Task Handlers](#creating-task-handlers)
    - [Task Handler YAML Configuration](#task-handler-yaml-configuration)
    - [Using the Task Handler](#using-the-task-handler)
  - [Step Handlers](#step-handlers)
    - [Key Methods](#key-methods)
  - [API Step Handlers](#api-step-handlers)
    - [API Step Handler Configuration](#api-step-handler-configuration)
  - [Defining Step Dependencies](#defining-step-dependencies)
    - [How Dependencies Work](#how-dependencies-work)
  - [Customizing Behavior](#customizing-behavior)
    - [Separating API Calls with `process`](#separating-api-calls-with-process)
    - [Processing Results](#processing-results)
    - [Customizing Result Processing](#customizing-result-processing)
    - [Accessing Data from Previous Steps](#accessing-data-from-previous-steps)
  - [Authentication \& Authorization](#authentication--authorization)
    - [Key Features](#key-features)
    - [Quick Start](#quick-start)
    - [Generators](#generators)
    - [GraphQL Security](#graphql-security)
    - [Complete Documentation](#complete-documentation)
  - [Best Practices](#best-practices)
  - [Event System \& Custom Integrations](#event-system--custom-integrations)
    - [Quick Start with Event Subscribers](#quick-start-with-event-subscribers)
  - [Event Subscribers vs Workflow Steps: Architectural Distinction](#event-subscribers-vs-workflow-steps-architectural-distinction)
    - [Use Event Subscribers For:](#use-event-subscribers-for)
    - [Use Workflow Steps For:](#use-workflow-steps-for)
    - [Examples of Proper Usage](#examples-of-proper-usage)
    - [Practical Examples](#practical-examples)
    - [Example: Custom Events in Step Handlers](#example-custom-events-in-step-handlers)
    - [Example Custom Subscriber](#example-custom-subscriber)
  - [Telemetry and Observability](#telemetry-and-observability)
  - [Documentation](#documentation)
    - [Developer Resources](#developer-resources)
    - [Additional Resources](#additional-resources)
  - [Scheduling Tasks](#scheduling-tasks)
  - [Dependencies](#dependencies)
  - [Development](#development)
  - [Gratitude](#gratitude)
  - [License](#license)

## Introduction

Tasker is a **production-ready Rails engine** that makes it easier to build complex, resilient workflows by organizing them into discrete steps that can be executed, retried, and tracked with sophisticated orchestration capabilities.

### 🚀 Core Capabilities
- **Complex Workflow Patterns**: Linear, diamond, tree, and parallel merge workflows
- **Intelligent Retry Logic**: Exponential backoff with configurable retry limits
- **Dependency Management**: Sophisticated DAG-based step dependencies
- **High-Performance Processing**: SQL-function based orchestration with 4x performance gains
- **Production Resilience**: Automatic failure recovery and retry orchestration
- **Complete Observability**: Event-driven architecture with comprehensive telemetry

Perfect for processes that:
- Involve multiple interdependent steps
- Require automatic retries with exponential backoff
- Have complex dependencies between steps
- Need to be queued and processed asynchronously
- Require visibility into progress, errors, and retry behavior
- Must handle transient failures gracefully

## Installation

Add Tasker to your Rails app's `Gemfile`:

```ruby
source 'https://rubygems.pkg.github.com/jcoletaylor' do
  gem 'tasker', '~> 2.1.0'
end
```

Install and run the migrations:

```bash
bundle exec rails tasker:install:migrations
bundle exec rails db:migrate
```

Mount the engine in your routes:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount Tasker::Engine, at: '/tasker', as: 'tasker'
end
```

Set up the initial configuration:

```bash
bundle exec rails tasker:setup
```

## Core Concepts

Tasker is built around a few key concepts:

- **Tasks**: The overall process to be executed
- **TaskHandlers**: Classes that define and coordinate the steps in a task
- **Steps**: Individual units of work within a task
- **StepHandlers**: Classes that implement the logic for each step
- **Dependencies**: Relationships between steps that determine execution order
- **Retry Logic**: Built-in mechanisms for retrying failed steps

## Creating Task Handlers

Task handlers define the workflow for a specific type of task. The easiest way to create a task handler is using the built-in generator:

```bash
rails generate tasker:task_handler OrderProcess
```

This creates:

- A task handler class in `app/tasks/order_process.rb`
- A YAML configuration in `config/tasker/tasks/order_process.yaml`
- A spec file in `spec/tasks/order_process_spec.rb`

### Task Handler YAML Configuration

The YAML configuration defines the task handler, its steps, and their relationships:

```yaml
---
name: order_process
module_namespace: # Optional namespace
task_handler_class: OrderProcess
concurrent: true # Whether steps can run concurrently

schema: # JSON Schema for validating task context
  type: object
  required:
    - order_id
  properties:
    order_id:
      type: integer

step_templates:
  - name: fetch_order
    description: Fetch order details from database
    handler_class: OrderProcess::StepHandler::FetchOrderHandler

  - name: validate_items
    description: Validate order items are available
    depends_on_step: fetch_order
    handler_class: OrderProcess::StepHandler::ValidateItemsHandler

  - name: process_payment
    description: Process payment for the order
    depends_on_step: validate_items
    handler_class: OrderProcess::StepHandler::ProcessPaymentHandler
    # Retry configuration
    default_retryable: true
    default_retry_limit: 3

  - name: update_inventory
    description: Update inventory levels
    depends_on_step: process_payment
    handler_class: OrderProcess::StepHandler::UpdateInventoryHandler

  - name: send_confirmation
    description: Send confirmation email
    depends_on_step: update_inventory
    handler_class: OrderProcess::StepHandler::SendConfirmationHandler
```

### Using the Task Handler

```ruby
# Create a task request
task_request = Tasker::Types::TaskRequest.new(
  name: 'order_process',
  context: { order_id: 12345 }
)

# Initialize the task
handler = Tasker::HandlerFactory.instance.get('order_process')
task = handler.initialize_task!(task_request)

# The task is now queued for processing
```

## Step Handlers

Step handlers implement the actual logic for each step in a task. They must define a `process` method that performs the work and returns the results:

```ruby
module OrderProcess
  module StepHandler
    class FetchOrderHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        # Get data from the task context
        order_id = task.context['order_id']

        # Perform the work
        order = Order.find(order_id)

        # Return results - they will be stored in step.results automatically
        { order: order.as_json }
      end
    end
  end
end
```

### Key Methods

- `process(task, sequence, step)`: Required method that executes the step's business logic and returns results
  - `task`: The Tasker::Task instance being processed
  - `sequence`: The Tasker::Types::StepSequence containing all steps
  - `step`: The current Tasker::WorkflowStep being executed
  - **Return value**: The results to be stored in `step.results` (handled automatically)

- `process_results(step, process_output, initial_results)`: Optional method to customize result storage
  - `step`: The current Tasker::WorkflowStep being executed
  - `process_output`: The return value from your `process()` method
  - `initial_results`: The value of `step.results` before `process()` was called
  - **Override this**: When you need to transform or format results before storing them

**Important**: Step lifecycle events are **automatically published** around your `process` method:
- `step_started` event fired before your method executes
- `step_completed` event fired after successful completion
- `step_failed` event fired if an exception occurs

Simply implement your business logic in `process()` and return your results - event publishing and result storage happen automatically!

⚠️  **Never override the `handle()` method** - it's framework-only code that coordinates event publishing and calls your `process()` method.

## API Step Handlers

Tasker includes a special base class for API-based steps that provides:

- HTTP request handling via Faraday
- Automatic retries with exponential backoff
- Support for rate limiting and server-requested backoff
- Response processing helpers

To create an API step handler, inherit from `Tasker::StepHandler::Api` and implement the `process` method:

```ruby
class FetchOrderStatusHandler < Tasker::StepHandler::Api
  def process(task, _sequence, _step)
    order_id = task.context['order_id']
    # Make the API call - returns Faraday::Response
    connection.get("/orders/#{order_id}/status")
  end

  # Override to customize how the API response is stored
  def process_results(step, process_output, initial_results)
    # Extract and transform the API response data
    if process_output.status == 200
      response_data = JSON.parse(process_output.body)
      step.results = {
        status: response_data['status'],
        last_updated: response_data['updated_at'],
        success: true
      }
    else
      step.results = {
        success: false,
        error: "API returned status #{process_output.status}"
      }
    end
  end
end
```

**Key Points:**
- ✅ **Always implement `process()`** - This makes your HTTP request
- ✅ **Optionally override `process_results()`** - For custom response processing
- ⚠️ **Never override `handle()`** - Framework-only method for event publishing and coordination

### API Step Handler Configuration

API Step Handlers can be configured in the YAML:

```yaml
- name: fetch_order_status
  handler_class: OrderProcess::StepHandler::FetchOrderStatusHandler
  handler_config:
    type: api
    url: https://api.example.com
    params:
      api_key: ${API_KEY}
    headers:
      Accept: application/json
    retry_delay: 1.0
    enable_exponential_backoff: true
```

## Defining Step Dependencies

Steps are executed in the order defined by their dependencies. There are two ways to define dependencies:

1. `depends_on_step`: Single dependency on another step
2. `depends_on_steps`: Multiple dependencies on other steps

```yaml
- name: send_notification
  description: Send notification about processed order
  # This step will only run after both payment and inventory steps complete
  depends_on_steps:
    - process_payment
    - update_inventory
  handler_class: OrderProcess::StepHandler::SendNotificationHandler
```

### How Dependencies Work

- Steps with no dependencies start first (root steps)
- When a step completes, Tasker checks for steps that depend on it
- When all dependencies for a step are complete, it becomes eligible for execution
- If concurrent processing is enabled, eligible steps run in parallel
- The task completes when all steps are processed

## Customizing Behavior

There are several ways to customize Tasker's behavior using the `process` method:

### Separating API Calls with `process`

For API step handlers, the `process` method is the developer extension point for making HTTP requests:

```ruby
class CartFetchStepHandler < Tasker::StepHandler::Api
  include ApiTask::ApiUtils

  def process(task, _sequence, _step)
    cart_id = task.context['cart_id']
    connection.get("/carts/#{cart_id}")
  end

  # Override process_results to do custom response processing
  def process_results(step, process_output, initial_results)
    # Extract and process the cart data from the API response
    step.results = get_from_results(process_output, 'cart')
  end
end
```

### Processing Results

For regular step handlers, implement your business logic in the `process` method:

```ruby
module OrderProcess
  module StepHandler
    class FetchOrderHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        # Get data from the task context
        order_id = task.context['order_id']

        # Perform the work
        order = Order.find(order_id)

        # Return results - they will be stored in step.results automatically
        { order: order.as_json }
      end
    end
  end
end
```

### Customizing Result Processing

If you need to customize how the return value from `process()` gets stored in `step.results`, you can override the `process_results()` method:

```ruby
class DataTransformHandler < Tasker::StepHandler::Base
  def process(task, sequence, step)
    # Your business logic that returns raw data
    raw_data = fetch_external_data(task.context)
    raw_data  # Return raw data
  end

  # Override to customize how results are stored
  def process_results(step, process_output, initial_results)
    # Transform the raw output before storing
    transformed_data = {
      processed_at: Time.current,
      data: process_output.transform_keys(&:underscore),
      record_count: process_output.size
    }

    step.results = transformed_data
  end
end
```

**Key Points:**
- The framework calls `process_results(step, process_output, initial_results)` after your `process()` method
- `process_output` is the return value from your `process()` method
- `initial_results` is the value of `step.results` before `process()` was called
- If you manually set `step.results` in your `process()` method, `process_results()` respects that and won't override it

### Accessing Data from Previous Steps

Steps often need data from previous steps:

```ruby
def process(_task, sequence, step)
  # Find a specific step by name
  cart_step = sequence.find_step_by_name('fetch_cart')

  # Access its results
  cart_data = cart_step.results['cart']

  # Use the data
  processed_cart = process_cart(cart_data)

  # Return your results
  { processed: true, cart_data: processed_cart }
end
```

## Authentication & Authorization

Tasker includes a complete, production-ready authentication and authorization system that provides enterprise-grade security for both REST APIs and GraphQL endpoints. The system is designed to work with any Rails authentication solution while maintaining flexibility and security.

### Key Features

- **🔐 Provider Agnostic**: Works seamlessly with Devise, JWT, OmniAuth, custom authentication, or no authentication
- **🛡️ Resource-Based Authorization**: Granular permissions using resource:action patterns (`tasker.task:create`, `tasker.workflow_step:show`)
- **⚡ GraphQL Operation-Level Authorization**: Revolutionary security that automatically maps GraphQL operations to resource permissions
- **🔄 Automatic Integration**: Authentication and authorization work seamlessly across REST and GraphQL endpoints
- **🚀 Production-Ready Generators**: Create complete authenticators and authorization coordinators with one command
- **✅ Zero Breaking Changes**: All features are opt-in and maintain backward compatibility

### Quick Start

```ruby
# config/initializers/tasker.rb
Tasker.configuration do |config|
  config.auth do |auth|
    # Enable authentication with your custom authenticator
    auth.authentication_enabled = true
    auth.authenticator_class = 'YourCustomAuthenticator'

    # Enable resource-based authorization
    auth.authorization_enabled = true
    auth.authorization_coordinator_class = 'YourAuthorizationCoordinator'
    auth.user_class = 'User'
  end
end
```

### Generators

Generate production-ready authenticators for popular authentication systems:

```bash
# JWT authenticator with comprehensive security features
rails generate tasker:authenticator CompanyJWT --type=jwt

# Devise integration with proper scope handling
rails generate tasker:authenticator AdminAuth --type=devise --user-class=Admin

# API token authenticator with header fallback
rails generate tasker:authenticator ApiAuth --type=api_token

# OmniAuth integration with session management
rails generate tasker:authenticator SocialAuth --type=omniauth

# Authorization coordinator with resource-based permissions
rails generate tasker:authorization_coordinator CompanyAuth
```

### GraphQL Security

The system provides revolutionary GraphQL authorization that automatically maps operations to permissions:

```ruby
# GraphQL query automatically requires tasker.task:index permission
query { tasks { taskId status } }

# GraphQL mutation automatically requires tasker.task:create permission
mutation { createTask(input: { name: "New Task" }) { taskId } }

# Mixed operations check all required permissions
query {
  tasks { taskId }           # Requires: tasker.task:index
  workflowSteps { stepId }   # Requires: tasker.workflow_step:index
}
```

### Complete Documentation

For comprehensive documentation including quick start guides, custom authenticator examples, authorization patterns, GraphQL security details, production best practices, and testing strategies:

**📖 See [Authentication & Authorization Guide](docs/AUTH.md)**

## Best Practices

1. **Keep steps focused**: Each step should do one thing well
2. **Use meaningful step names**: Names should clearly indicate what the step does
3. **Store useful data in step results**: Include enough information for dependent steps
4. **Handle errors gracefully**: Use begin/rescue and set appropriate error information
5. **Configure retries appropriately**: Set retry limits based on the reliability of the operation
6. **Use API step handlers for external services**: Take advantage of built-in retry and backoff
7. **Test with mocked dependencies**: Create tests that verify step behavior in isolation
8. **Document step dependencies**: Make it clear why steps depend on each other

```ruby
# Example 1: Let exceptions bubble up (Recommended)
def process(task, sequence, step)
  # Attempt the operation - let exceptions propagate naturally
  result = perform_complex_operation(task.context)
  { success: true, data: result }

  # Framework automatically handles exceptions:
  # - Publishes step_failed event with error details
  # - Stores error information in step.results
  # - Transitions step to error state
  # - Triggers retry logic if configured
end

# Example 2: Catch, record error details, then re-raise
def process(task, sequence, step)
  begin
    result = perform_complex_operation(task.context)
    { success: true, data: result }
  rescue StandardError => e
    # Add custom error context to step.results
    step.results = {
      error: e.message,
      error_type: e.class.name,
      custom_context: "Additional business context",
      retry_recommended: should_retry?(e)
    }
    # Re-raise so framework knows this step failed
    raise
  end
end

# Example 3: Treat handled exceptions as success
def process(task, sequence, step)
  begin
    result = perform_complex_operation(task.context)
    { success: true, data: result }
  rescue RecoverableError => e
    # This exception is handled and considered a success case
    # Step will be marked as COMPLETED, not failed
    {
      success: true,
      data: get_fallback_data(task.context),
      recovered_from_error: e.message,
      used_fallback: true
    }
  end
end
```

## Event System & Custom Integrations

Tasker features a comprehensive event-driven architecture that provides deep insights into task execution and enables powerful integrations. The event system includes:

- **Complete Event Catalog** - Discover all available events with `Tasker::Events.catalog` and `Tasker::Events.complete_catalog`
- **Custom Business Events** - Define and publish custom events from step handlers for business logic observability
- **Custom Event Subscribers** - Create integrations with external services (Sentry, PagerDuty, Slack)
- **Subscriber Generator** - `rails generate tasker:subscriber` creates subscribers with automatic method routing
- **Event Discovery** - Search and filter events by namespace, name, or description
- **Production-Ready Observability** - OpenTelemetry integration with comprehensive telemetry
- **Living Documentation** - Real-world integration examples with comprehensive test coverage

### Quick Start with Event Subscribers

```bash
# Generate a subscriber for critical alerts
rails generate tasker:subscriber pager_duty --events task.failed step.failed

# Generate a notification subscriber
rails generate tasker:subscriber notification --events task.completed task.failed

# Generate a specialized metrics subscriber with helper methods
rails generate tasker:subscriber metrics --metrics --events task.completed task.failed step.completed step.failed
```

## Event Subscribers vs Workflow Steps: Architectural Distinction

**Critical Design Principle**: Event subscribers should handle **"collateral" or "secondary" logic** - operations that support observability, monitoring, and alerting but are not core business requirements.

### Use Event Subscribers For:
- **Operational Observability**: Logging, metrics, telemetry, traces
- **Alerting & Monitoring**: Sentry errors, PagerDuty alerts, Slack notifications
- **Analytics**: Business intelligence, usage tracking, performance monitoring
- **External Integrations**: Non-critical third-party service notifications

### Use Workflow Steps For:
- **Business-Critical Operations**: Actions that must succeed for the workflow to be considered complete
- **Operations Requiring**:
  - **Idempotency**: Can be safely retried without side effects
  - **Retryability**: Built-in retry logic with exponential backoff
  - **Explicit Lifecycle Tracking**: Success/failure states that matter to the business
  - **Transactional Integrity**: Operations that need to be rolled back on failure

### Examples of Proper Usage

**✅ Event Subscriber (Collateral Concerns)**:
```ruby
class ObservabilitySubscriber < Tasker::Events::Subscribers::BaseSubscriber
  subscribe_to 'order.fulfilled'

  def handle_order_fulfilled(event)
    # Operational logging and analytics - if these fail, the order is still fulfilled
    AnalyticsService.track_fulfillment(order_id: safe_get(event, :order_id))
    Rails.logger.info "Order #{safe_get(event, :order_id)} fulfilled"
  end
end
```

**✅ Workflow Step (Business Logic)**:
```yaml
# config/tasker/tasks/order_process.yaml
- name: send_confirmation_email
  description: Send order confirmation email to customer
  depends_on_step: process_payment
  handler_class: OrderProcess::StepHandler::SendConfirmationEmailHandler
  default_retryable: true
  default_retry_limit: 3
```

**❌ Wrong - Business Logic in Event Subscriber**:
```ruby
# DON'T DO THIS - Critical email sending belongs in a workflow step
def handle_order_fulfilled(event)
  CustomerService.send_confirmation_email(safe_get(event, :order_id))  # Critical business action!
end
```

### Practical Examples

**Sending Customer Emails**:
- ✅ **Workflow Step**: Order confirmation email (customer expects this, must be delivered)
- ✅ **Event Subscriber**: Internal team notification about order (operational awareness)

**External API Calls**:
- ✅ **Workflow Step**: Charging payment gateway (business transaction must succeed)
- ✅ **Event Subscriber**: Sending metrics to DataDog (operational monitoring)

**Database Operations**:
- ✅ **Workflow Step**: Updating inventory levels (business state change)
- ✅ **Event Subscriber**: Logging order details for analytics (operational insight)

**Message Queues**:
- ✅ **Workflow Step**: Publishing order to fulfillment queue (business requirement)
- ✅ **Event Subscriber**: Publishing metrics to monitoring queue (operational data)

### Example: Custom Events in Step Handlers

```ruby
class OrderFulfillmentStep < Tasker::StepHandler::Base
  def self.custom_event_configuration
    [
      { name: 'order.fulfilled', description: 'Order has been fulfilled and shipped' }
    ]
  end

  def process(task, sequence, step)
    order = fulfill_order(task.context['order_id'])

    # Publish custom business event for collateral systems to observe
    publish_custom_event('order.fulfilled', {
      order_id: order.id,
      customer_id: order.customer_id,
      total_amount: order.total
    })

    { order_id: order.id, fulfillment_date: Time.current }
  end
end
```

### Example Custom Subscriber

```ruby
class ObservabilitySubscriber < Tasker::Events::Subscribers::BaseSubscriber
  # Subscribe to system and custom events for observability/alerting purposes
  subscribe_to 'task.completed', 'task.failed', 'order.fulfilled', 'payment.risk_flagged'

  # Log task completion for operational visibility
  def handle_task_completed(event)
    task_id = safe_get(event, :task_id)
    task_name = safe_get(event, :task_name, 'unknown')
    execution_duration = safe_get(event, :execution_duration, 0)

    # Operational logging and metrics (collateral concerns)
    Rails.logger.info "Task completed: #{task_name} (#{task_id}) in #{execution_duration}s"
    StatsD.histogram('tasker.task.duration', execution_duration, tags: ["task:#{task_name}"])
  end

  # Alert on task failures for operational response
  def handle_task_failed(event)
    task_id = safe_get(event, :task_id)
    error_message = safe_get(event, :error_message, 'Unknown error')

    # Send alerts to operational tools (collateral concerns)
    Sentry.capture_message("Task failed: #{task_id}", level: 'error', extra: { error: error_message })
    PagerDutyService.trigger_alert(
      summary: "Tasker workflow failed",
      severity: 'error',
      details: { task_id: task_id, error: error_message }
    )
  end

  # Monitor business events for analytics/alerting
  def handle_order_fulfilled(event)
    order_id = safe_get(event, :order_id)
    customer_id = safe_get(event, :customer_id)

    # Analytics and operational monitoring (collateral concerns)
    AnalyticsService.track_order_fulfillment(order_id, customer_id)
    Rails.logger.info "Order fulfilled: #{order_id} for customer #{customer_id}"
  end

  def handle_payment_risk_flagged(event)
    risk_score = safe_get(event, :risk_score, 0)

    # Alert on high-risk payments for operational response
    if risk_score > 0.8
      PagerDutyService.trigger_alert(
        summary: "High-risk payment detected",
        severity: 'warning',
        details: event
      )
    end
  end
end
```

For complete documentation on the event system, subscriber creation, and integration examples, see [docs/EVENT_SYSTEM.md](docs/EVENT_SYSTEM.md).

## Telemetry and Observability

Tasker includes comprehensive telemetry capabilities to provide insights into task execution flow and performance:

- **Built-in OpenTelemetry integration** for compatibility with tools like Jaeger, Zipkin, and Honeycomb
- **Standardized event naming** for consistent observability across task and step operations
- **Automatic span creation** with proper parent-child relationships for complex workflows
- **Sensitive data filtering** to ensure security and privacy of telemetry data
- **Configurable service naming** to customize how traces appear in your observability tools
- **Detailed event lifecycle tracking** with standard events for all task and step operations

For complete documentation on telemetry features, configuration options, and best practices, see [docs/TELEMETRY.md](docs/TELEMETRY.md).

## Documentation

### Developer Resources

- **[Developer Guide](docs/DEVELOPER_GUIDE.md)** - Comprehensive guide covering task handlers, step handlers, event subscribers, and YAML configuration
- **[Authentication Guide](docs/AUTH.md)** - Complete authentication system documentation with JWT, Devise, and custom authenticator examples
- **[Event System](docs/EVENT_SYSTEM.md)** - Complete event system documentation with integration examples
- **[Telemetry & Observability](docs/TELEMETRY.md)** - OpenTelemetry integration and custom monitoring setup
- **[System Overview](docs/OVERVIEW.md)** - Architecture overview and configuration examples
- **[Workflow Execution](docs/FLOW_CHART.md)** - Visual guide to workflow execution and retry logic

### Additional Resources

- **[Why Tasker](docs/WHY.md)** - Background and motivation for building Tasker
- **[Task Diagrams](docs/TASK_DIAGRAM.md)** - Visual representation of task workflows

## Scheduling Tasks

Tasker does not directly manage scheduling recurring tasks. There are a variety of strategies that already exist in the Rails ecosystem for accomplishing this. [Javan's Whenever gem](https://github.com/javan/whenever) is one of the most popular, and is very battle-tested.

## Dependencies

- Ruby version - 3.2.2
- System dependencies - Postgres, Redis, and Sidekiq (in development and test environments)

## Development

- Database - `bundle exec rake db:schema:load`
- How to run the test suite - `bundle exec rspec spec`
- Lint: `bundle exec rubocop`

## Gratitude

Flowchart PNG by [xnimrodx](https://www.flaticon.com/authors/xnimrodx) from [Flaticon](https://www.flaticon.com/)

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
