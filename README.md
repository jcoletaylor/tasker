[![CI](https://github.com/jcoletaylor/tasker/actions/workflows/main.yml/badge.svg)](https://github.com/jcoletaylor/tasker/actions/workflows/main.yml)
![GitHub](https://img.shields.io/github/license/jcoletaylor/tasker)
![GitHub release (latest SemVer)](https://img.shields.io/github/v/release/jcoletaylor/tasker?color=blue&sort=semver)

# Tasker: Production-Ready Workflow Orchestration Engine

## What is Tasker?

Tasker is a **production-ready Rails engine** that transforms complex, multi-step processes into reliable, observable workflows. It handles the orchestration complexity so you can focus on your business logic.

### 🚀 Key Capabilities
- **Complex Workflow Patterns**: Linear, diamond, tree, and parallel merge workflows
- **Intelligent Retry Logic**: Exponential backoff with configurable retry limits
- **Production Resilience**: Automatic failure recovery and retry orchestration
- **Complete Observability**: Event-driven architecture with comprehensive telemetry
- **Enterprise Security**: Authentication & authorization with GraphQL operation-level permissions
- **High Performance**: SQL-function based orchestration with 4x performance gains

Perfect for processes that involve multiple interdependent steps, require automatic retries, need visibility into progress and errors, and must handle transient failures gracefully.

## Quick Installation

Add Tasker to your Rails app's `Gemfile`:

```ruby
source 'https://rubygems.pkg.github.com/jcoletaylor' do
  gem 'tasker', '~> 2.3.0'
end
```

Install and run the migrations:

```bash
bundle exec rails tasker:install:migrations
bundle exec rails db:migrate
```

Mount the engine and set up configuration:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount Tasker::Engine, at: '/tasker', as: 'tasker'
end
```

```bash
bundle exec rails tasker:setup
```

## Core Concepts

Tasker organizes workflows around these key concepts:

- **Tasks**: The overall process to be executed
- **TaskNamespaces**: Organizational hierarchy for grouping related task types
- **TaskHandlers**: Classes that define and coordinate workflow steps
- **Steps**: Individual units of work within a task
- **StepHandlers**: Classes that implement the logic for each step
- **Dependencies**: Relationships between steps that determine execution order
- **Versioning**: Semantic versioning support for task handlers with coexistence

### TaskNamespace Organization

Tasker supports organizing task handlers into logical namespaces for better organization and isolation:

```ruby
# Different namespaces can have tasks with the same name
payments_task = Tasker::HandlerFactory.instance.get(
  'process_order',
  namespace_name: 'payments',
  version: '2.1.0'
)

inventory_task = Tasker::HandlerFactory.instance.get(
  'process_order',
  namespace_name: 'inventory',
  version: '1.5.0'
)
```

Common namespace patterns:
- **`payments`** - Payment processing workflows
- **`inventory`** - Stock and inventory management
- **`notifications`** - Email, SMS, and alert workflows
- **`integrations`** - Third-party API integrations
- **`data_processing`** - ETL and data transformation workflows
- **`default`** - General-purpose workflows (used when no namespace specified)

## Simple Example: Order Processing

Create a task handler for processing orders:

```bash
rails generate tasker:task_handler OrderProcess
```

This creates a complete workflow structure:

**YAML Configuration** (`config/tasker/tasks/order_process.yaml`):
```yaml
---
name: order_process
namespace_name: default
version: 1.0.0
task_handler_class: OrderProcess
concurrent: true

step_templates:
  - name: validate_order
    description: Validate order details
    handler_class: OrderProcess::StepHandler::ValidateOrderHandler

  - name: process_payment
    description: Process payment for the order
    depends_on_step: validate_order
    handler_class: OrderProcess::StepHandler::ProcessPaymentHandler
    default_retryable: true
    default_retry_limit: 3

  - name: send_confirmation
    description: Send confirmation email
    depends_on_step: process_payment
    handler_class: OrderProcess::StepHandler::SendConfirmationHandler
```

**Step Handler Implementation**:
```ruby
module OrderProcess
  module StepHandler
    class ValidateOrderHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        order_id = task.context['order_id']
        order = Order.find(order_id)

        raise "Order not found" unless order
        raise "Order already processed" if order.processed?

        { order: order.as_json, valid: true }
      end
    end
  end
end
```

**Using Your Workflow**:
```ruby
# Create and execute a task
task_request = Tasker::Types::TaskRequest.new(
  name: 'order_process',
  namespace: 'default',        # Optional - defaults to 'default'
  version: '1.0.0',           # Optional - defaults to '0.1.0'
  context: { order_id: 12345 }
)

# Handler lookup now supports namespace + version
handler = Tasker::HandlerFactory.instance.get(
  'order_process',
  namespace_name: 'default',   # Optional - defaults to 'default'
  version: '1.0.0'            # Optional - defaults to '0.1.0'
)
task = handler.initialize_task!(task_request)

# Task is now queued for processing with automatic retry logic
```

## Advanced Features

### Authentication & Authorization

Tasker includes enterprise-grade security that works with any Rails authentication system:

```ruby
# config/initializers/tasker.rb
Tasker.configuration do |config|
  config.auth do |auth|
    auth.authentication_enabled = true
    auth.authenticator_class = 'YourAuthenticator'
    auth.authorization_enabled = true
    auth.authorization_coordinator_class = 'YourAuthorizationCoordinator'
  end
end
```

**Automatic GraphQL Security**: Operations are automatically mapped to permissions:
```ruby
# GraphQL query automatically requires tasker.task:index permission
query { tasks { taskId status } }

# GraphQL mutation automatically requires tasker.task:create permission
mutation { createTask(input: { name: "New Task" }) { taskId } }
```

### REST API & Handler Discovery

Tasker provides comprehensive REST API endpoints for handler discovery, task management, and dependency graph analysis:

**Handler Discovery API**:
```bash
# List all namespaces with handler counts
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     https://your-app.com/tasker/handlers

# List handlers in specific namespace
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     https://your-app.com/tasker/handlers/payments

# Get handler details with dependency graph
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     https://your-app.com/tasker/handlers/payments/process_order?version=2.1.0
```

**Response includes dependency graph visualization**:
```json
{
  "id": "process_order",
  "namespace": "payments",
  "version": "2.1.0",
  "step_templates": [...],
  "dependency_graph": {
    "nodes": ["validate_order", "process_payment", "send_confirmation"],
    "edges": [
      {"from": "validate_order", "to": "process_payment"},
      {"from": "process_payment", "to": "send_confirmation"}
    ],
    "execution_order": ["validate_order", "process_payment", "send_confirmation"]
  }
}
```

**Task Management API**:
```bash
# Create task with namespace/version support
curl -X POST -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"name": "process_order", "namespace": "payments", "version": "2.1.0", "context": {"order_id": 123}}' \
     https://your-app.com/tasker/tasks

# List tasks with namespace filtering
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     "https://your-app.com/tasker/tasks?namespace=payments&version=2.1.0"
```

### Event System & Integrations

Tasker provides comprehensive event-driven observability for custom integrations:

```ruby
class OrderEventsSubscriber < Tasker::Events::Subscribers::BaseSubscriber
  subscribe_to 'task.completed', 'task.failed'

  def handle_task_completed(event)
    task_id = safe_get(event, :task_id)
    NotificationService.send_success_email(task_id: task_id)
  end

  def handle_task_failed(event)
    task_id = safe_get(event, :task_id)
    error_message = safe_get(event, :error_message)
    AlertService.send_failure_alert(task_id: task_id, error: error_message)
  end
end
```

### Telemetry & Observability

Built-in OpenTelemetry integration provides complete observability:

```ruby
# config/initializers/tasker.rb
Tasker.configuration do |config|
  config.telemetry do |tel|
    tel.enabled = true
    tel.service_name = 'my-app-workflows'
    tel.service_version = '1.0.0'
  end
end
```

Compatible with Jaeger, Zipkin, Honeycomb, and other OpenTelemetry-compatible tools.

### Health Monitoring & Production Readiness

Tasker provides enterprise-grade health endpoints for production deployments:

```ruby
# Kubernetes readiness probe - checks database connectivity
GET /tasker/health/ready

# Kubernetes liveness probe - lightweight health check
GET /tasker/health/live

# Detailed status endpoint - comprehensive system metrics
GET /tasker/health/status
```

**Optional Authentication & Authorization**:
```ruby
# config/initializers/tasker.rb
Tasker.configuration do |config|
  config.health do |health|
    health.status_requires_authentication = true  # Secure detailed status
  end

  config.auth do |auth|
    auth.authorization_enabled = true
    # Status endpoint requires tasker.health_status:index permission
  end
end
```

**Performance Optimized**: Uses SQL functions and 15-second caching for sub-100ms response times.

## Key Benefits

### For Developers
- **Quick Setup**: Working workflows in minutes with generators
- **Clear Structure**: YAML configuration with Ruby implementation
- **Comprehensive Testing**: Built-in test infrastructure and patterns
- **Rich Documentation**: Extensive guides and examples

### For Operations
- **Production Ready**: Battle-tested retry logic and error handling
- **Health Monitoring**: Enterprise-grade health endpoints for K8s and load balancers
- **Observable**: Complete event system with telemetry integration
- **Secure**: Enterprise-grade authentication and authorization
- **Performant**: SQL-function based orchestration with proven performance

### For Business
- **Reliable**: Automatic retry with exponential backoff
- **Scalable**: Handles complex workflows with multiple dependencies
- **Maintainable**: Clear separation of concerns and documented patterns
- **Extensible**: Event system enables custom integrations

## What's Next?

### 🚀 Get Started Quickly
- **[Quick Start Guide](docs/QUICK_START.md)** - Build your first workflow in 15 minutes
- **[Developer Guide](docs/DEVELOPER_GUIDE.md)** - Comprehensive implementation guide
- **[Examples](spec/examples/)** - Real-world workflow patterns and implementations

### 🔧 Advanced Topics
- **[REST API Guide](docs/REST_API.md)** - Complete REST API documentation with handler discovery
- **[Authentication & Authorization](docs/AUTH.md)** - Complete security system
- **[Health Monitoring](docs/HEALTH.md)** - Production health endpoints and monitoring
- **[Event System](docs/EVENT_SYSTEM.md)** - Observability and integrations
- **[Telemetry](docs/TELEMETRY.md)** - OpenTelemetry setup and monitoring
- **[Performance](docs/SQL_FUNCTIONS.md)** - High-performance SQL functions

### 📚 Additional Resources
- **[System Overview](docs/OVERVIEW.md)** - Architecture and configuration
- **[Task Diagrams](docs/TASK_DIAGRAM.md)** - Visual workflow representation
- **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Common issues and solutions

## Requirements & Dependencies

- **Ruby**: 3.2+
- **Rails**: 7.2+
- **Database**: PostgreSQL (required for SQL functions)
- **Background Jobs**: Compatible with ActiveJob (Sidekiq recommended)

## Development & Testing

```bash
# Set up development environment
bundle install
bundle exec rake db:schema:load

# Run tests
bundle exec rspec spec

# Run linter
bundle exec rubocop
```

## Contributing

We welcome contributions! Please see our [development guidelines](docs/DEVELOPER_GUIDE.md) for information on setting up your development environment and our coding standards.

## License

The gem is available as open source under the terms of the [MIT License](./LICENSE).

---

**Tasker** transforms complex workflows into reliable, observable processes. Focus on your business logic while Tasker handles the orchestration complexity.
