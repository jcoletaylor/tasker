[![CI](https://github.com/jcoletaylor/tasker/actions/workflows/main.yml/badge.svg)](https://github.com/jcoletaylor/tasker/actions/workflows/main.yml)
![GitHub](https://img.shields.io/github/license/jcoletaylor/tasker)
![GitHub release (latest SemVer)](https://img.shields.io/github/v/release/jcoletaylor/tasker?color=blue&sort=semver)

# Tasker: Queable Multi-Step Tasks Made Easy-ish

Designed to make developing queuable multi-step tasks easier to reason about

![Flowchart](flowchart.png "Tasker")

## Getting Started with Tasker

This guide will walk you through the fundamentals of using Tasker to build complex task workflows with retries, error handling, and concurrency.

## Table of Contents

- [Tasker: Queable Multi-Step Tasks Made Easy-ish](#tasker-queable-multi-step-tasks-made-easy-ish)
  - [Getting Started with Tasker](#getting-started-with-tasker)
  - [Table of Contents](#table-of-contents)
  - [Introduction](#introduction)
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
  - [Best Practices](#best-practices)
  - [Event System \& Custom Integrations](#event-system--custom-integrations)
    - [Quick Start with Event Subscribers](#quick-start-with-event-subscribers)
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

Tasker is a Rails engine that makes it easier to build complex workflows by organizing them into discrete steps that can be executed, retried, and tracked. It's designed for processes that:

- Involve multiple steps
- May need retries with exponential backoff
- Have dependencies between steps
- Should be queued and processed asynchronously
- Need visibility into progress and errors

## Installation

Add Tasker to your Rails app's `Gemfile`:

```ruby
source 'https://rubygems.pkg.github.com/jcoletaylor' do
  gem 'tasker', '~> 1.6.0'
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
rails generate task_handler OrderProcess
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
# Example of good error handling
def process(task, sequence, step)
  begin
    # Attempt the operation
    result = perform_complex_operation(task.context)
    { success: true, data: result }
  rescue StandardError => e
    # Return error information - framework will still publish step_failed event
    {
      success: false,
      error: e.message,
      error_type: e.class.name,
      backtrace: e.backtrace.first(5).join("\n")
    }
    # Re-raise to trigger retry logic
    raise
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
```

### Example: Custom Events in Step Handlers

```ruby
# Register custom business events
Tasker::Events.register_custom_event('order.fulfilled',
  description: 'Order has been fulfilled and shipped')

# Publish from step handlers
class OrderFulfillmentStep < Tasker::StepHandler::Base
  def handle(step)
    order = fulfill_order(step.inputs['order_id'])

    # Publish custom business event
    publish_custom_event('order.fulfilled', {
      order_id: order.id,
      customer_id: order.customer_id,
      total_amount: order.total
    })
  end
end
```

### Example Custom Subscriber

```ruby
class NotificationSubscriber < Tasker::Events::Subscribers::BaseSubscriber
  # Subscribe to system and custom events
  subscribe_to 'task.completed', 'task.failed', 'order.fulfilled'

  # Handle task completion events
  def handle_task_completed(event)
    task_id = safe_get(event, :task_id)
    NotificationService.send_success_email(task_id: task_id)
  end

  # Handle failure events
  def handle_task_failed(event)
    task_id = safe_get(event, :task_id)
    error_message = safe_get(event, :error_message, 'Unknown error')
    AlertService.send_failure_alert(task_id: task_id, error: error_message)
  end

  # Handle custom business events
  def handle_order_fulfilled(event)
    order_id = safe_get(event, :order_id)
    customer_id = safe_get(event, :customer_id)
    NotificationService.send_fulfillment_notification(
      order_id: order_id,
      customer_id: customer_id
    )
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
