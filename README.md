[![CI](https://github.com/jcoletaylor/tasker/actions/workflows/main.yml/badge.svg)](https://github.com/jcoletaylor/tasker/actions/workflows/main.yml)

# Tasker: Queable Multi-Step Tasks Made Easy-ish

## *Designed to make developing queuable multi-step tasks easier to reason about*

![Flowchart](flowchart.png "Tasker")


## Quickstart

Add to your Rails `Gemfile`

```ruby
# add to your Gemfile
source 'https://rubygems.pkg.github.com/jcoletaylor' do
  gem 'tasker', '~> 0.2.3'
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

## How to use Tasker

Of course first you'll have to add it to your Gemfile and install it, as above.

Building a TaskHandler looks something like this:

```ruby
class DummyTask
  include Tasker::TaskHandler

  # these are just for readability, they could just be strings elsewhere
  DUMMY_SYSTEM = 'dummy-system'
  STEP_ONE = 'step-one'
  STEP_TWO = 'step-two'
  STEP_THREE = 'step-three'
  STEP_FOUR = 'step-four'
  STEP_FIVE = 'step-five'
  TASK_REGISTRY_NAME = 'dummy_task'

  # this is for convenience to read, it could be any class that has a handle method with this signature
  class Handler
    # the handle method is only expected to catch around recoverable errors
    # it is responsible for setting results back on the step
    def handle(_task, _sequence, step)
      # task and sequence are passed in case the task context or the sequence's prior steps
      # may contain data that is necessary for the handling of this step
      step.results = { dummy: true }
    end
  end

  # register the task handler with the handler factory
  register_handler(TASK_REGISTRY_NAME)

  # define steps for the step handlers
  # only name and handler_class are required, but others help with visibility and findability
  define_step_templates do |templates|
    templates.define(
      dependent_system: DUMMY_SYSTEM,
      name: STEP_ONE,
      description: 'Independent Step One',
      # these are the defaults, omitted elsewhere for brevity
      default_retryable: true,
      default_retry_limit: 3,
      skippable: false,
      handler_class: DummyTask::Handler
    )
    templates.define(
      dependent_system: DUMMY_SYSTEM,
      name: STEP_TWO,
      description: 'Independent Step Two',
      handler_class: DummyTask::Handler
    )
    templates.define(
      dependent_system: DUMMY_SYSTEM,
      name: STEP_THREE,
      depends_on_step: STEP_TWO,
      description: 'Step Three Dependent on Step Two',
      handler_class: DummyTask::Handler
    )
    templates.define(
      dependent_system: DUMMY_SYSTEM,
      name: STEP_FOUR,
      depends_on_step: STEP_THREE,
      description: 'Step Four Dependent on Step Three',
      handler_class: DummyTask::Handler
    )
  end

  # this should conform to the json-schema gem's expectations for how to validate json
  # used to validate the context of a given TaskRequest whether from the API or otherwise
  def schema
    @schema ||= { type: :object, required: [:dummy], properties: { dummy: { type: 'boolean' } } }
  end
end

```

## TODO

A full [TODO](./TODO.md).
## Dependencies

* Ruby version - 2.7

* System dependencies - Postgres, Redis, and Sidekiq

## Development

* Database - `bundle exec rake db:schema:load`

* How to run the test suite - `bundle exec rspec spec`

* Lint: `bundle exec rake lint`

* Typecheck with Sorbet: `bundle exec srb tc`
## Gratitude

Flowchart PNG by [xnimrodx](https://www.flaticon.com/authors/xnimrodx) from [Flaticon](https://www.flaticon.com/) 

## License
The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
