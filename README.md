[![CI](https://github.com/jcoletaylor/tasker/actions/workflows/main.yml/badge.svg)](https://github.com/jcoletaylor/tasker/actions/workflows/main.yml)
![GitHub](https://img.shields.io/github/license/jcoletaylor/tasker)
![GitHub release (latest SemVer)](https://img.shields.io/github/v/release/jcoletaylor/tasker?color=blue&sort=semver)

# Tasker: Queable Multi-Step Tasks Made Easy-ish

## *Designed to make developing queuable multi-step tasks easier to reason about*

![Flowchart](flowchart.png "Tasker")

## Quickstart

Add to your Rails `Gemfile`

```ruby
# add to your Gemfile
source 'https://rubygems.pkg.github.com/jcoletaylor' do
  gem 'tasker', '~> 1.2.0'
end
```

Add the migrations in your Rails app root:

```bash
bundle exec rake tasker:install:migrations
bundle exec rake db:migrate
```

And then mount it where you'd like in `config/routes.rb` with:

```ruby
# config/routes.rb

Rails.application.routes.draw do
  mount Tasker::Engine, at: '/tasker', as: 'tasker'
end
```

## Usage

### Creating a Task Handler from scratch

1. Create a new task handler class in `app/task_handlers/my_task.rb`
2. Define the steps in the task handler class
3. Register the task handler with the Tasker registry

Full examples of this can be reviewed as an [API integration example](./spec/examples/api_task/integration_example.rb).

However, the most common pattern is to use a YAML file to define the task handler.

### Creating a Configured Task Handler

1. Create a YAML file defining your task handler following the structure above
2. Place it in an appropriate directory, e.g., `app/task_handlers/my_task.yaml`
3. Develop your step handlers as normal classes, and reference them in the YAML file
4. API-backed step handlers which inherit from `Tasker::StepHandler::Api` will automatically use exponential backoff and jitter
5. Task steps are organized as a Directed Acyclic Graph (DAG) to ensure proper ordering of execution, and if concurrency is not disabled, will automatically execute in parallel where dependencies allow

### Example of creating a Configured Task Handler

```ruby
module MyModule
  class MyYamlTask < Tasker::ConfiguredTask
    def self.yaml_path
      Rails.root.join('app/task_handlers/my_task.yaml')
    end
  end
end

# Usage:
handler = MyModule::MyYamlTask.new
# The class is already built and ready to use
# though this of course requires the step handler classes referenced in the YAML to be defined
# as that is the core of your business logic
```

### Example of a Configured Task Handler

Here's an example YAML file for an e-commerce API integration task handler:

```yaml
---
name: api_integration_yaml_task
module_namespace: ApiTask
class_name: IntegrationYamlExample
concurrent: true

default_dependent_system: ecommerce_system

named_steps:
  - fetch_cart
  - fetch_products
  - validate_products
  - create_order
  - publish_event

schema:
  type: object
  required:
    - cart_id
  properties:
    cart_id:
      type: integer

step_templates:
  - name: fetch_cart
    description: Fetch cart details from e-commerce system
    handler_class: ApiTask::StepHandler::CartFetchStepHandler
    handler_config:
      type: api
      url: https://api.ecommerce.com/cart
      params:
        cart_id: 1

  - name: fetch_products
    description: Fetch product details from product catalog
    handler_class: ApiTask::StepHandler::ProductsFetchStepHandler
    handler_config:
      type: api
      url: https://api.ecommerce.com/products

  - name: validate_products
    description: Validate product availability
    depends_on_steps:
      - fetch_products
      - fetch_cart
    handler_class: ApiTask::StepHandler::ProductsValidateStepHandler

  - name: create_order
    description: Create order from validated cart
    depends_on_step: validate_products
    handler_class: ApiTask::StepHandler::CreateOrderStepHandler

  - name: publish_event
    description: Publish order created event
    depends_on_step: create_order
    handler_class: ApiTask::StepHandler::PublishEventStepHandler
```

## API Task Example

See the [examples/api_task](./spec/examples/api_task) directory for an example of a task handler that processes an e-commerce order through a series of steps, interacting with external systems, and handling errors and retries. You can read more about the example [here](./spec/examples/api_task/README.md).

### API Routes

Tasker provides a RESTful API for managing tasks. Here are the available endpoints:

#### Tasks

- `GET /tasker/tasks` - List all tasks
- `POST /tasker/tasks` - Create and enqueue a new task
- `GET /tasker/tasks/{task_id}` - Get task details
- `PATCH/PUT /tasker/tasks/{task_id}` - Update task
- `DELETE /tasker/tasks/{task_id}` - Cancel task

#### Workflow Steps

- `GET /tasker/tasks/{task_id}/workflow_steps` - List steps for a task
- `GET /tasker/tasks/{task_id}/workflow_steps/{step_id}` - Get step details
- `PATCH/PUT /tasker/tasks/{task_id}/workflow_steps/{step_id}` - Update step
- `DELETE /tasker/tasks/{task_id}/workflow_steps/{step_id}` - Cancel step

### Creating a Task via API

Example of creating a task using curl:

```bash
curl -X POST https://www.example.com/tasker/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "name": "api_integration_task",
    "context": {
      "cart_id": 123
    },
    "initiator": "web_interface",
    "reason": "Process new order",
    "source_system": "ecommerce",
    "tags": ["order_processing", "api_integration"]
  }'
```

The request body must include:

- `name`: The name of the task handler to use
- `context`: A JSON object containing the task's context data
- `initiator`: Who/what initiated the task
- `reason`: Why the task was created
- `source_system`: The system that created the task
- `tags`: (Optional) Array of tags for categorization

## Why build this?

That's a good question - Tasker is a pretty specialized kind of abstraction that many organizations may never really need. But as event-driven architectures become the norm, and as even smaller organizations find themselves interacting with a significant number of microservices, SaaS platforms, data stores, event queues, and the like, managing this complexity becomes a problem at scale.

## Doesn't Sidekiq already exist? (or insert your favorite queuing broker)

It does! I love [Sidekiq](https://sidekiq.org/) and Tasker is built on top of it. But this solves a little bit of a different problem.

In event-driven architectures, it is not uncommon for the successful completion of any single "task" to actually be dependent on a significant number of "steps" - and these steps often rely on interacting with a number of different external and internal systems, whether an external API, a local datastore, or an in-house microservice. The success of a given task is therefore dependent on the successful completion of each step, and steps can likewise be dependent on other steps.

The task itself may be enqueued for processing more than once, while steps are in a backoff or retry state. There are situations where a task and all of it steps may be able to be processed sequentially and successfully completed. In this case, the first time a task is enqueued, it is processed to completion, and will not be enqueued again. However, there are situations where a step's status is still in a valid state, but not complete, waiting on other steps, waiting on remote backoff requests, waiting on retrying from a remote failure, etc. When working with integrated services, APIs, etc that may fail, having retryability and resiliency around *each step* is crucial. If a step fails, it can be retried up to its retry limit, before we consider it in a final-error state. It is only a task which has one or more steps in a final-error (no retries left) that would mark a task as itself in error and no longer re-enquable. Any task that has still-viable steps that cannot be processed immediately, will simply be re-enqueued. The task and its steps retain the state of inputs, outputs, successes, and failures, so that implementing logic for different workflows do not have to repeat this logic over and over.

## Consider an Example

Consider a common scenario of receiving an e-commerce order in a multi-channel sales scenario, where fulfillment is managed on-site by an organization. Fulfillment systems have different data stores than the e-commerce solution, of course, but changes to an "order" in the abstract may have mutual effects on both the e-commerce representation of an order and the fulfillment order. When a change should be made to one, very frequently that change should, in some manner, propagate to both. Or, similarly, when an order is shipped, perhaps final taxes need to be calculated and reported to a tax SaaS platform, have the response data stored, and finally in total synced to a data warehouse for financial consistency. The purpose of Tasker is to make it more straightforward to enable event-driven architectures to handle multi-step tasks in a consistent and predictable way, with exposure to visibility in terms of results, status of steps, retryability, timeouts and backoffs, etc.

## Technology Choices

I originally developed this as a [standalone application](https://github.com/jcoletaylor/tasker_rails), but it felt like this would be a really good opportunity to convert it to a Rails Engine. For my day-to-day professional life I've been working pretty deeply with microservices and domain driven design patterns, but my current role has me back in a Rails monolith - in some ways, it feels good to be home! However, if we were ever going to use something like this in my current role, we would want it to be an Engine so it could be built and maintained external to our existing architecture.

For this Rails Engine, I'm not going to include a lot of the sample lower-level handlers that the standalone application has written in Rust. However, you can [checkout the writeup](https://github.com/jcoletaylor/tasker_rails#technology-choices) in that app if you're interested!

## TODO

A full [TODO](./docs/TODO.md).

## Dependencies

- Ruby version - 3.2.2
- System dependencies - Postgres, Redis, and Sidekiq

## Development

- Database - `bundle exec rake db:schema:load`
- How to run the test suite - `bundle exec rspec spec`
- Lint: `bundle exec rubocop`

## Gratitude

Flowchart PNG by [xnimrodx](https://www.flaticon.com/authors/xnimrodx) from [Flaticon](https://www.flaticon.com/)

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
