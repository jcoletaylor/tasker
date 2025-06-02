# Custom Events Configuration

## Overview

Tasker's YAML-driven event system now supports configurable directories for loading developer-space custom events. This provides tremendous flexibility for organizing event definitions across different domains, modules, or gems.

## Configuration

### Default Location (Recommended)

By default, Tasker loads custom events from:

- `config/tasker/events/*.yml` - **The standard location for custom events**

This provides a clear, canonical location for your custom event definitions.

### Basic Configuration

For most applications, simply place your event YAML files in `config/tasker/events/`:

```
config/
  tasker/
    events/
      orders.yml       # order.created, order.cancelled, order.shipped
      payments.yml     # payment.attempted, payment.completed, payment.failed
      notifications.yml # notification.sent, notification.failed
```

No configuration required! This is the recommended approach for most use cases.

### Advanced Configuration (When Needed)

If you need additional directories for complex organizational needs:

```ruby
# config/initializers/tasker.rb
Tasker.configuration do |config|
  # Add custom directories while keeping the default
  config.add_custom_events_directories(
    'vendor/gems/my_analytics_gem/events',
    'lib/shared_events',
    'app/modules/billing/events'
  )
end
```

### Replacing the Default (Not Recommended)

Only use this if you have specific requirements:

```ruby
# config/initializers/tasker.rb
Tasker.configuration do |config|
  # Replace the default entirely (not recommended for most cases)
  config.custom_events_directories = [
    'my/custom/events/path',
    'another/custom/path'
  ]
end
```

### Default Directory

The default directory is: `config/tasker/events/`

All `.yml` files in this directory are automatically loaded. No configuration needed!

## Organization Strategies

### 1. Recommended: Domain-Based Files (Default Directory)

The simplest and most recommended approach - organize by domain within the standard directory:

```
config/
  tasker/
    events/
      orders.yml       # order.created, order.cancelled, order.shipped
      payments.yml     # payment.attempted, payment.completed, payment.failed
      customers.yml    # customer.created, customer.updated
      notifications.yml # notification.sent, notification.failed
```

**No configuration required!** Just add files to `config/tasker/events/`.

### 2. Advanced: Multiple Custom Directories

Only use this approach if you have specific organizational requirements:

#### Module-Based Organization

For applications with distinct modules:

```
app/
  modules/
    billing/
      events/
        subscription.yml  # subscription.created, subscription.cancelled
        invoice.yml       # invoice.generated, invoice.paid
    analytics/
      events/
        tracking.yml      # event.tracked, report.generated
```

**Configuration:**
```ruby
config.add_custom_events_directories(
  'app/modules/billing/events',
  'app/modules/analytics/events'
)
```

#### Gem-Based Organization

For Rails engines or gems that contribute events:

```
vendor/
  gems/
    my_analytics_gem/
      events/
        tracking.yml
lib/
  my_gem/
    events/
      custom.yml
```

**Configuration:**
```ruby
config.add_custom_events_directories(
  'vendor/gems/my_analytics_gem/events',
  'lib/my_gem/events'
)
```

#### Environment-Specific Events

Different events for different environments:

```
config/
  tasker/
    events/
      base.yml         # Common events for all environments
    environments/
      development/
        debug.yml      # debug.trace, debug.performance
      production/
        monitoring.yml # monitor.alert, monitor.health_check
```

**Configuration:**
```ruby
config.add_custom_events_directories(
  "config/tasker/environments/#{Rails.env}"
)
```

## Event File Structure

Each YAML file follows this structure:

```yaml
---
# Domain-specific events
events:
  custom:
    order_created:
      constant: "order.created"
      description: "Fired when a new order is created"
      payload_schema:
        order_id: { type: "String", required: true }
        customer_id: { type: "String", required: true }
        total_amount: { type: "Float", required: true }
        timestamp: { type: "Time", required: true }
      fired_by: ["OrderService", "CheckoutController"]

    order_cancelled:
      constant: "order.cancelled"
      description: "Fired when an order is cancelled"
      payload_schema:
        order_id: { type: "String", required: true }
        cancellation_reason: { type: "String", required: true }
        timestamp: { type: "Time", required: true }
      fired_by: ["OrderService"]
```

## Key Features

### Automatic Namespace Protection

- **Developers use clean names**: `"order.created"`, `"payment.failed"`
- **System adds prefix internally**: `"custom.order.created"`, `"custom.payment.failed"`
- **Prevents conflicts**: System events like `"task.completed"` are protected

### Multiple File Support

- Load from individual files: `config/tasker/events.yml`
- Load from directories: `config/events/*.yml`
- Mix files and directories in configuration

### Path Resolution

- **Relative paths**: Resolved from Rails application root
- **Absolute paths**: Used as-is
- **Flexible formats**: Supports both `.yml` and `.yaml` extensions

### Error Handling

- **Graceful failures**: Missing directories logged but don't break startup
- **Validation**: Schema validation ensures event definitions are complete
- **Conflict detection**: Duplicate event constants are detected and reported

## Event Loading Process

When your Rails application starts:

1. **System Events**: Load from Tasker gem (`config/tasker/system_events.yml`)
2. **Custom Events**: Load from all configured directories
3. **Validation**: Check for duplicate constants and required fields
4. **Registration**: Register all events with the publisher

## Usage Examples

### Publishing Custom Events

```ruby
class OrderService
  include Tasker::Concerns::EventPublisher

  def create_order(params)
    order = Order.create!(params)

    # Publish using clean event name
    publish_event('order.created', {
      order_id: order.id,
      customer_id: order.customer_id,
      total_amount: order.total,
      timestamp: Time.current
    })

    order
  end
end
```

### Subscribing to Custom Events

```ruby
class OrderNotificationSubscriber < Tasker::Events::Subscribers::BaseSubscriber
  # Subscribe using clean event names
  subscribe_to 'order.created', 'order.cancelled'

  def handle_order_created(event)
    order_id = safe_get(event, :order_id)
    OrderConfirmationMailer.send_confirmation(order_id).deliver_later
  end

  def handle_order_cancelled(event)
    order_id = safe_get(event, :order_id)
    OrderCancellationMailer.send_cancellation(order_id).deliver_later
  end
end

# Register the subscriber
OrderNotificationSubscriber.subscribe(Tasker::Events::Publisher.instance)
```

## Best Practices

### 1. Organize by Business Domain
- Group related events together
- Use descriptive directory names
- Keep files focused on specific domains

### 2. Use Consistent Naming
- Follow `domain.action` pattern: `order.created`, `payment.failed`
- Use past tense for completed actions
- Be specific but concise

### 3. Document Event Usage
- Include clear descriptions in YAML files
- Specify who fires each event (`fired_by`)
- Define comprehensive payload schemas

### 4. Plan for Scale
- Start with simple organization
- Refactor as your event system grows
- Consider gem boundaries for shared events

### 5. Test Your Configuration
- Verify events load correctly in each environment
- Test path resolution with your directory structure
- Validate event definitions regularly

## Troubleshooting

### Directory Not Found
If you see debug messages about missing directories, check:
- Path spelling and case sensitivity
- Relative vs absolute path resolution
- Directory permissions

### Events Not Loading
Common issues:
- YAML syntax errors in event files
- Missing required fields in event definitions
- Duplicate event constants across files

### Path Resolution Issues
- Use `Rails.root.join('path')` for complex path construction
- Test with `bundle exec rails runner` to verify paths
- Check Rails.env-specific path resolution

## Migration from Hardcoded Paths

If you're upgrading from a version with hardcoded event paths:

### Before
Events only loaded from:
- `config/tasker/events.yml` (single file)
- `config/tasker/events/*.yml` (directory)

### After
**Recommended default:**
- `config/tasker/events/*.yml` (simplified to one clear location)

**Optional custom directories:**
- Add additional directories via `config.add_custom_events_directories()` when needed

### Migration Steps
1. **No action required** for existing setups - `config/tasker/events/*.yml` still works
2. **Recommended**: Consolidate events into `config/tasker/events/` for simplicity
3. **Configure custom paths** only if you have specific organizational requirements

### Example Migration

**Before (still works):**
```
config/tasker/events.yml         # Single file approach
config/tasker/events/orders.yml  # Directory approach
```

**After (recommended):**
```
config/tasker/events/orders.yml     # Clean, consistent approach
config/tasker/events/payments.yml
config/tasker/events/customers.yml
```

This configuration system provides a clear default path while maintaining flexibility for complex organizational needs.
