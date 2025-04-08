# Tasker Telemetry

This document describes how to use Tasker's telemetry features to gain visibility into task execution.

## Overview

Tasker provides a telemetry system that captures lifecycle events for tasks and steps, allowing you to monitor and debug your workflows. The telemetry system is designed to be non-intrusive and to have no impact on the actual execution of tasks.

Key features:

- Capture all meaningful task and step lifecycle events
- Support for multiple simultaneous adapters (Rails logger, OpenTelemetry, and custom)
- Easy opt-in configuration
- Distributed tracing support via OpenTelemetry

## Lifecycle Events

Tasker captures the following lifecycle events:

### Task Events

| Event | Description |
|-------|-------------|
| `task.initialize` | Task is created from a task request |
| `task.start` | Task processing begins |
| `task.handle` | Task handler is invoked |
| `task.enqueue` | Task is queued for processing |
| `task.finalize` | Task processing is being finalized |
| `task.complete` | Task has completed successfully |
| `task.error` | Task has failed |

### Step Events

| Event | Description |
|-------|-------------|
| `step.find_viable` | Viable steps are identified for execution |
| `step.handle` | Step processing begins |
| `step.complete` | Step has completed successfully |
| `step.error` | Step has failed |
| `step.retry` | Step is being retried |
| `step.skip` | Step is skipped |
| `step.max_retries_reached` | Maximum retry attempts reached for a step |

## Configuration

### Basic Configuration

To enable telemetry, update your `config/initializers/tasker.rb` file:

```ruby
Tasker.configuration do |config|
  # Enable telemetry
  config.enable_telemetry = true

  # Use the default Rails logger adapter (default)
  config.telemetry_adapters = [:default]
end
```

### Using Multiple Adapters

You can use multiple telemetry adapters simultaneously:

```ruby
Tasker.configuration do |config|
  config.enable_telemetry = true

  # Use both Rails logger and OpenTelemetry
  config.telemetry_adapters = [:default, :opentelemetry]
end
```

This allows you to have standard Rails logging while also gaining distributed tracing capabilities.

### OpenTelemetry Configuration

For distributed tracing with OpenTelemetry:

First, run the setup task:

```bash
bundle exec rake tasker:telemetry:setup
```

This will:

- Add OpenTelemetry gems to your Gemfile
- Create a sample OpenTelemetry initializer at `config/initializers/opentelemetry.rb`

Then, edit the initializer to configure your OpenTelemetry settings.

Finally, install the gems:

```bash
bundle install
```

## Custom Telemetry Adapters

You can create your own telemetry adapters by:

1. Creating classes that inherit from `Tasker::Telemetry::Adapter`
2. Implementing the required methods
3. Configuring Tasker to use your adapters:

```ruby
Tasker.configuration do |config|
  config.enable_telemetry = true

  # Use both default adapter and a custom one
  config.telemetry_adapters = [:default, :custom, :custom]

  # Provide class names for each :custom entry in telemetry_adapters
  config.telemetry_adapter_classes = [
    'MyApp::CustomTelemetryAdapter',
    'MyApp::AnotherCustomAdapter'
  ]
end
```

## Telemetry Adapter Interface

Custom adapters must implement this interface:

```ruby
class MyAdapter < Tasker::Telemetry::Adapter
  # Required method - record an event with payload
  def record(event, payload = {})
    # Implementation
  end

  # Optional method - start a new trace
  def start_trace(name, attributes = {})
    # Implementation
  end

  # Optional method - end the current trace
  def end_trace
    # Implementation
  end

  # Optional method - add a span to the current trace
  def add_span(name, attributes = {}, &block)
    # Implementation
    yield if block_given?
  end
end
```

## Manually Recording Events

If you need to record custom events in your task handlers:

```ruby
Tasker::Telemetry.record('custom.event', { key: 'value' })
```

## OpenTelemetry Integration

When using the OpenTelemetry adapter:

- Each task creates a trace
- Each step creates a span within the task trace
- Events are added as span events
- Task and step attributes are attached to spans
- Error information is captured automatically

This allows you to visualize your complete workflow execution in any OpenTelemetry-compatible backend.

## Relationship Between Lifecycle Events and Telemetry

The Tasker codebase fires lifecycle events through the `Tasker::LifecycleEvents` module. The `Tasker::Telemetry::Observer` listens for these events and routes them to the configured telemetry adapters.

This means:
1. All telemetry is driven by lifecycle events
2. You can add observers that use these events for purposes other than telemetry
3. The system is extensible while maintaining separation of concerns
