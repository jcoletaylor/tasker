# Registry System Architecture

## Overview

Tasker features enterprise-grade registry systems that provide thread-safe operations, comprehensive validation, structured logging, and event integration. All registry systems have been modernized to use `Concurrent::Hash` storage and unified patterns.

## Registry Systems

### HandlerFactory Registry

The core registry for task handler management with namespace and version support.

**Features**:
- **Thread-Safe Operations**: `Concurrent::Hash` storage eliminates race conditions
- **3-Level Registry**: `namespace_name → handler_name → version → handler_class`
- **Interface Validation**: Fail-fast validation with detailed error messages
- **Conflict Resolution**: `replace: true` parameter for graceful updates
- **Structured Logging**: Every operation logged with correlation IDs

**Usage**:
```ruby
# Thread-safe registration
Tasker::HandlerFactory.instance.register(
  'payment_processor',
  PaymentHandler,
  namespace_name: 'payments',
  version: '2.1.0',
  replace: true  # Handles conflicts gracefully
)

# Thread-safe retrieval
handler = Tasker::HandlerFactory.instance.get(
  'payment_processor',
  namespace_name: 'payments',
  version: '2.1.0'
)

# List handlers in namespace
handlers = Tasker::HandlerFactory.instance.list_handlers(namespace: 'payments')

# Registry statistics
stats = Tasker::HandlerFactory.instance.stats
# => {
#   total_handlers: 45,
#   namespaces: ["payments", "inventory", "notifications"],
#   versions: ["1.0.0", "1.1.0", "2.0.0"],
#   thread_safe: true,
#   last_registration: "2024-01-15T10:30:45Z"
# }
```

### PluginRegistry System

Format-based plugin discovery with auto-discovery capabilities for telemetry exporters.

**Features**:
- **Format-Based Discovery**: Register plugins by export format (`:json`, `:csv`, `:prometheus`)
- **Auto-Discovery**: Automatic plugin detection and registration
- **Thread-Safe Operations**: Mutex-synchronized operations
- **Interface Validation**: Method arity checking for plugin interfaces
- **Event Integration**: Plugin registration triggers event system

**Usage**:
```ruby
# Register custom exporter
Tasker::Telemetry::PluginRegistry.register(
  'custom_json_exporter',
  CustomJsonExporter,
  format: :json,
  replace: true
)

# Find plugins by format
json_exporters = Tasker::Telemetry::PluginRegistry.find_by(format: :json)

# Auto-discovery
Tasker::Telemetry::PluginRegistry.auto_discover_plugins

# Registry statistics
stats = Tasker::Telemetry::PluginRegistry.stats
# => {
#   total_plugins: 12,
#   formats: [:json, :csv, :prometheus],
#   auto_discovery_enabled: true,
#   thread_safe: true
# }
```

### SubscriberRegistry System

Centralized event subscriber management with comprehensive validation.

**Features**:
- **Centralized Management**: Single registry for all event subscribers
- **Event Validation**: Validates subscriber methods match event names
- **Thread-Safe Operations**: Concurrent access protection
- **Health Monitoring**: Built-in health checks and statistics
- **Auto-Registration**: Automatic registration during class loading

**Usage**:
```ruby
# Register event subscriber
Tasker::Registry::SubscriberRegistry.register(
  'notification_subscriber',
  NotificationSubscriber,
  events: ['task.completed', 'task.failed']
)

# List subscribers for event
subscribers = Tasker::Registry::SubscriberRegistry.find_by_event('task.completed')

# Registry health check
health = Tasker::Registry::SubscriberRegistry.health_check
# => { status: "healthy", subscriber_count: 15, events_covered: 45 }
```

## Structured Logging

Every registry operation includes comprehensive structured logging with correlation IDs:

```json
{
  "timestamp": "2024-01-15T10:30:45Z",
  "correlation_id": "tsk_abc123_def456",
  "component": "handler_factory",
  "message": "Registry item registered",
  "environment": "production",
  "tasker_version": "2.4.1",
  "process_id": 12345,
  "thread_id": "abc123",
  "entity_type": "task_handler",
  "entity_id": "payments/payment_processor/2.1.0",
  "entity_class": "PaymentHandler",
  "registry_name": "handler_factory",
  "options": {
    "namespace_name": "payments",
    "version": "2.1.0",
    "replace": true
  },
  "event_type": "registered"
}
```

## Interface Validation

All registries include fail-fast validation with detailed error messages:

```ruby
# Example validation error
begin
  Tasker::HandlerFactory.instance.register('invalid_handler', InvalidClass)
rescue Tasker::Registry::ValidationError => e
  puts e.message
  # => "Handler validation failed: InvalidClass does not implement required method 'process'.
  #     Required methods: [process, initialize_task!].
  #     Available methods: [initialize, new].
  #     Suggestion: Inherit from Tasker::TaskHandler::Base"
end
```

## Event Integration

Registry operations are fully integrated with Tasker's 56-event system:

**Registry Events**:
- `registry.handler_registered` - Handler registration events
- `registry.plugin_registered` - Plugin registration events
- `registry.subscriber_registered` - Subscriber registration events
- `registry.validation_failed` - Validation failure events
- `registry.conflict_resolved` - Conflict resolution events

**Event Payloads**:
```ruby
# Handler registration event
{
  registry_type: 'handler_factory',
  entity_id: 'payments/payment_processor/2.1.0',
  entity_class: 'PaymentHandler',
  namespace_name: 'payments',
  version: '2.1.0',
  options: { replace: true },
  correlation_id: 'tsk_abc123'
}
```

## Thread Safety

All registry systems use thread-safe storage and operations:

**Storage Types**:
- **HandlerFactory**: `Concurrent::Hash` with nested concurrent structures
- **PluginRegistry**: `Concurrent::Hash` with mutex synchronization
- **SubscriberRegistry**: `Concurrent::Hash` with atomic operations

**Thread Safety Guarantees**:
- **Atomic Operations**: Registration and retrieval are atomic
- **Race Condition Prevention**: No partial state during concurrent access
- **Memory Consistency**: All threads see consistent registry state
- **Deadlock Prevention**: Proper lock ordering and timeout handling

## Health Monitoring

Built-in health monitoring and statistics for all registries:

```ruby
# Individual registry health
handler_health = Tasker::HandlerFactory.instance.health_check
plugin_health = Tasker::Telemetry::PluginRegistry.health_check
subscriber_health = Tasker::Registry::SubscriberRegistry.health_check

# Comprehensive registry system health
registry_health = Tasker::Registry.system_health
# => {
#   status: "healthy",
#   registries: {
#     handler_factory: { status: "healthy", count: 45 },
#     plugin_registry: { status: "healthy", count: 12 },
#     subscriber_registry: { status: "healthy", count: 15 }
#   },
#   thread_safe: true,
#   total_entities: 72
# }
```

## Performance Characteristics

**Registry Operation Performance**:
- **Registration**: O(1) average case with thread-safe operations
- **Retrieval**: O(1) lookup with concurrent access
- **Listing**: O(n) where n is entities in scope
- **Statistics**: O(1) with cached computation

**Memory Usage**:
- **Efficient Storage**: Minimal memory overhead per registered entity
- **Concurrent Structures**: Memory-safe concurrent access
- **Garbage Collection**: Proper cleanup and memory management

## Best Practices

### Registration Patterns

```ruby
# ✅ Good: Use replace parameter for updates
Tasker::HandlerFactory.instance.register(
  'payment_processor',
  PaymentHandler,
  namespace_name: 'payments',
  version: '2.1.0',
  replace: true
)

# ❌ Avoid: Registration without conflict handling
Tasker::HandlerFactory.instance.register(
  'payment_processor',
  PaymentHandler,
  namespace_name: 'payments',
  version: '2.1.0'
  # Will raise error if already exists
)
```

### Error Handling

```ruby
# ✅ Good: Handle validation errors gracefully
begin
  Tasker::HandlerFactory.instance.register(name, handler_class, options)
rescue Tasker::Registry::ValidationError => e
  logger.error "Handler registration failed: #{e.message}"
  # Handle error appropriately
rescue Tasker::Registry::ConflictError => e
  logger.warn "Handler conflict: #{e.message}"
  # Decide whether to use replace: true
end
```

### Performance Optimization

```ruby
# ✅ Good: Batch operations when possible
handlers = Tasker::HandlerFactory.instance.list_handlers(namespace: 'payments')
handlers.each { |name, versions| process_handler(name, versions) }

# ❌ Avoid: Individual lookups in loops
payment_handlers.each do |name|
  handler = Tasker::HandlerFactory.instance.get(name, namespace_name: 'payments')
  process_handler(handler)
end
```

## Troubleshooting

### Common Issues

**Thread Safety Issues**:
```ruby
# Symptom: Inconsistent registry state
# Solution: Ensure all access goes through registry APIs
# ❌ Don't access internal storage directly
# ✅ Use registry methods for all operations
```

**Validation Failures**:
```ruby
# Symptom: Registration fails with validation error
# Solution: Ensure classes implement required interfaces
class MyHandler < Tasker::TaskHandler::Base
  # Implements required methods automatically
end
```

**Memory Leaks**:
```ruby
# Symptom: Growing memory usage
# Solution: Use proper cleanup in test environments
after(:each) do
  Tasker::HandlerFactory.instance.clear_test_handlers!
end
```

### Debugging Registry State

```ruby
# Check registry contents
puts Tasker::HandlerFactory.instance.stats.to_json

# Verify thread safety
puts Tasker::HandlerFactory.instance.health_check[:thread_safe]

# Monitor registration events
Tasker::Events.subscribe('registry.handler_registered') do |event|
  puts "Handler registered: #{event[:entity_id]}"
end
```

## Migration Guide

### Upgrading from Legacy Registry

If upgrading from older Tasker versions:

1. **Update Registration Code**:
```ruby
# Old (pre-2.3.0)
Tasker::HandlerFactory.register('handler', HandlerClass)

# New (2.3.0+)
Tasker::HandlerFactory.instance.register(
  'handler',
  HandlerClass,
  namespace_name: 'default',
  version: '1.0.0'
)
```

2. **Handle Thread Safety**:
```ruby
# Old: Manual synchronization required
# New: Thread safety built-in
```

3. **Update Error Handling**:
```ruby
# Old: Generic exceptions
# New: Specific validation and conflict errors
```

## Related Documentation

- [Developer Guide](DEVELOPER_GUIDE.md) - HandlerFactory usage patterns
- [Event System](EVENT_SYSTEM.md) - Registry event integration
- [Telemetry](TELEMETRY.md) - Plugin registry usage
- [Health Monitoring](HEALTH.md) - Registry health endpoints
