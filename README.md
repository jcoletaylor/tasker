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
    - [Override the `handle` Method](#override-the-handle-method)
    - [Separating API Calls with `call`](#separating-api-calls-with-call)
    - [Processing Results](#processing-results)
    - [Accessing Data from Previous Steps](#accessing-data-from-previous-steps)
  - [Best Practices](#best-practices)
  - [Telemetry and Observability](#telemetry-and-observability)
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
- A YAML configuration in `config/tasks/order_process.yaml`
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

Step handlers implement the actual logic for each step in a task. They must define a `handle` method that performs the work:

```ruby
module OrderProcess
  module StepHandler
    class FetchOrderHandler
      def handle(task, sequence, step)
        # Get data from the task context
        order_id = task.context['order_id']

        # Perform the work
        order = Order.find(order_id)

        # Store results in the step
        step.results = { order: order.as_json }
      end
    end
  end
end
```

### Key Methods

- `handle(task, sequence, step)`: Required method that executes the step
  - `task`: The Tasker::Task instance being processed
  - `sequence`: The Tasker::Types::StepSequence containing all steps
  - `step`: The current Tasker::WorkflowStep being executed

## API Step Handlers

Tasker includes a special base class for API-based steps that provides:

- HTTP request handling via Faraday
- Automatic retries with exponential backoff
- Support for rate limiting and server-requested backoff
- Response processing helpers

To create an API step handler, inherit from `Tasker::StepHandler::Api` and implement the `call` method:

```ruby
class FetchOrderStatusHandler < Tasker::StepHandler::Api
  def call(task, _sequence, _step)
    order_id = task.context['order_id']
    # Make the API call using the provided connection
    connection.get("/orders/#{order_id}/status")
  end

  # Optionally, override handle to process results
  def handle(task, sequence, step)
    # Let the parent class handle the API call and set results
    super

    # Process the results further if needed
    status_data = step.results&.body&.dig('data', 'status')
    step.results = { status: status_data }
  end
end
```

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

There are several ways to customize Tasker's behavior:

### Override the `handle` Method

The `handle` method is the primary entry point for step execution. Override it to implement custom logic:

```ruby
# Example from spec/dummy/app/tasks/api_task/step_handler.rb
class CartFetchStepHandler < Tasker::StepHandler::Api
  include ApiTask::ApiUtils

  def call(task, _sequence, _step)
    cart_id = task.context['cart_id']
    connection.get("/carts/#{cart_id}")
  end

  # Override handle while keeping the parent class behavior
  def handle(_task, _sequence, step)
    # Call super to get the API handling and retry logic
    super
    # Then extract and transform the results
    step.results = get_from_results(step.results, 'cart')
  end
end
```

### Separating API Calls with `call`

For API step handlers, the `call` method simplifies making requests:

```ruby
def call(task, _sequence, _step)
  # Focus only on building and making the request
  # The parent class's handle method will call this method
  # and handle retries and exponential backoff
  user_id = task.context['user_id']
  connection.get("/users/#{user_id}/profile")
end
```

### Processing Results

You can process and transform API responses by overriding `handle`:

```ruby
def handle(task, sequence, step)
  # Let the parent class make the API call
  super

  # Now the response is in step.results
  # Extract what you need and transform
  if step.results.status == 200
    data = JSON.parse(step.results.body)
    step.results = { profile: data['user_profile'] }
  else
    raise "API error: #{step.results.status}"
  end
end
```

### Accessing Data from Previous Steps

Steps often need data from previous steps:

```ruby
def handle(_task, sequence, step)
  # Find a specific step by name
  cart_step = sequence.find_step_by_name('fetch_cart')

  # Access its results
  cart_data = cart_step.results['cart']

  # Use the data
  process_cart(cart_data)

  # Store your own results
  step.results = { processed: true }
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
def handle(task, sequence, step)
  begin
    # Attempt the operation
    result = perform_complex_operation(task.context)
    step.results = { success: true, data: result }
  rescue StandardError => e
    # Record detailed error information
    step.results = {
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

## Telemetry and Observability

Tasker includes comprehensive telemetry capabilities to provide insights into task execution flow and performance:

- **Built-in OpenTelemetry integration** for compatibility with tools like Jaeger, Zipkin, and Honeycomb
- **Standardized event naming** for consistent observability across task and step operations
- **Automatic span creation** with proper parent-child relationships for complex workflows
- **Sensitive data filtering** to ensure security and privacy of telemetry data
- **Configurable service naming** to customize how traces appear in your observability tools
- **Detailed event lifecycle tracking** with standard events for all task and step operations

For complete documentation on telemetry features, configuration options, and best practices, see [TELEMETRY.md](docs/TELEMETRY.md).

For more information on why I built this, see the [WHY.md](./docs/WHY.md) file.

For a system overview, see the [OVERVIEW.md](./docs/OVERVIEW.md) file, and the full [TODO](./docs/TODO.md).

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
