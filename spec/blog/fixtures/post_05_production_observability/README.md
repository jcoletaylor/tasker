# Post 05: Production Observability

This directory contains the production observability examples for the Tasker blog post "When Your Workflows Become Black Boxes".

## Overview

Post 05 demonstrates how to use Tasker's built-in event system and telemetry features to achieve comprehensive production observability. Instead of building custom monitoring into step handlers, we leverage Tasker's event-driven architecture.

## Key Components

### Event Subscribers

The observability solution is built using event subscribers that listen to Tasker's built-in events:

1. **BusinessMetricsSubscriber** (`business_metrics_subscriber.rb`)
   - Tracks checkout conversion rates
   - Monitors revenue impact of failures
   - Identifies workflow bottlenecks
   - Captures payment and inventory metrics

2. **PerformanceMonitoringSubscriber** (`performance_monitoring_subscriber.rb`)
   - Monitors task and step execution times
   - Tracks SLA compliance
   - Captures system resource usage
   - Calculates error rates and retry patterns

3. **AlertGenerationSubscriber** (`alert_generation_subscriber.rb`)
   - Generates business-aware alerts
   - Monitors for high-value customer failures
   - Detects performance degradation
   - Alerts on revenue impact thresholds

4. **DistributedTracingSubscriber** (`distributed_tracing_subscriber.rb`)
   - Adds correlation IDs to all events
   - Creates OpenTelemetry-compatible spans
   - Tracks parent-child relationships
   - Enriches events with trace context

### Monitored Workflow

The `monitored_checkout_handler.yaml` defines a simple e-commerce checkout workflow that generates events for our subscribers to observe:

- `validate_cart` - Validates cart contents
- `process_payment` - Processes payment through gateway
- `update_inventory` - Updates inventory levels
- `create_order` - Creates order record
- `send_confirmation` - Sends order confirmation

## Event System Architecture

```
Workflow Execution → Tasker Events → Event Subscribers → Observability
                                           ↓
                                    - Metrics (Prometheus)
                                    - Traces (Jaeger)
                                    - Alerts (PagerDuty)
                                    - Logs (Structured)
```

## Key Patterns Demonstrated

### 1. Event-Driven Observability
Instead of adding monitoring code to business logic, we observe events:
```ruby
on 'tasker.task.completed' do |event|
  # Track business metrics from task completion
end
```

### 2. Business Context Enrichment
Events include business context for meaningful observability:
```ruby
context[:customer_tier] # Track premium vs standard customers
context[:order_value]   # Calculate revenue impact
```

### 3. Distributed Tracing
Automatic correlation across all workflow steps:
```ruby
correlation_id: event.payload[:correlation_id]
trace_id: generate_trace_id
```

### 4. SLA Monitoring
Track against business-defined SLAs:
```ruby
handler_config:
  monitoring:
    sla_seconds: 45
```

## Testing

The test suite demonstrates:
- Event subscriber registration and lifecycle
- Business metrics calculation from events
- Alert generation based on thresholds
- Distributed trace context propagation

## Real-World Benefits

This approach provides:
- **Zero business logic pollution** - Monitoring stays separate from business code
- **Consistent observability** - All workflows automatically observable
- **Flexible integration** - Easy to add new monitoring tools
- **Production debugging** - Complete execution traces with business context

## Integration with Tasker

These examples integrate with Tasker's:
- Built-in event system (56+ events)
- Telemetry configuration
- Metrics backend
- OpenTelemetry support

See the main blog post for the complete narrative and production incident examples.