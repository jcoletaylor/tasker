# Tasker REST API Guide

## Overview

Tasker provides a comprehensive REST API for handler discovery, task management, and dependency graph analysis. The API supports namespace-based organization and semantic versioning, enabling enterprise-scale workflow management.

## Base URL & Mounting

The API is available at the mount point configured in your Rails routes:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount Tasker::Engine, at: '/tasker', as: 'tasker'
end
```

**Base URL**: `https://your-app.com/tasker`

## Authentication

All API endpoints support the same authentication system configured for your Tasker installation:

### JWT Authentication
```bash
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     -H "Content-Type: application/json" \
     https://your-app.com/tasker/handlers
```

### Custom Authentication
If you've configured a custom authenticator, use the authentication method appropriate for your setup:

```ruby
# config/initializers/tasker.rb
Tasker.configuration do |config|
  config.auth do |auth|
    auth.authentication_enabled = true
    auth.authenticator_class = 'YourCustomAuthenticator'
  end
end
```

## Handler Discovery API

The handler discovery API provides comprehensive information about available task handlers, their configurations, and dependency graphs.

### List Namespaces

**Endpoint**: `GET /tasker/handlers`

**Description**: Returns all namespaces with handler counts and metadata.

**Example Request**:
```bash
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     https://your-app.com/tasker/handlers
```

**Example Response**:
```json
{
  "namespaces": [
    {
      "name": "payments",
      "description": "Payment processing workflows",
      "handler_count": 5,
      "handlers": ["process_payment", "refund_payment", "validate_card", "process_subscription", "cancel_subscription"]
    },
    {
      "name": "inventory",
      "description": "Inventory management workflows",
      "handler_count": 3,
      "handlers": ["update_stock", "process_order", "check_availability"]
    },
    {
      "name": "notifications",
      "description": "Notification and messaging workflows",
      "handler_count": 4,
      "handlers": ["send_email", "send_sms", "push_notification", "alert_admin"]
    }
  ]
}
```

### List Handlers in Namespace

**Endpoint**: `GET /tasker/handlers/{namespace}`

**Description**: Returns all handlers available in a specific namespace.

**Parameters**:
- `namespace` (path) - The namespace name (e.g., "payments", "inventory")

**Example Request**:
```bash
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     https://your-app.com/tasker/handlers/payments
```

**Example Response**:
```json
{
  "namespace": "payments",
  "handlers": [
    {
      "id": "process_payment",
      "namespace": "payments",
      "version": "2.1.0",
      "description": "Process customer payment with validation and confirmation",
      "step_count": 4,
      "step_names": ["validate_payment", "charge_card", "update_order", "send_confirmation"]
    },
    {
      "id": "refund_payment",
      "namespace": "payments",
      "version": "1.5.0",
      "description": "Process customer refund with validation",
      "step_count": 3,
      "step_names": ["validate_refund", "process_refund", "notify_customer"]
    }
  ]
}
```

### Get Handler Details with Dependency Graph

**Endpoint**: `GET /tasker/handlers/{namespace}/{name}`

**Description**: Returns detailed handler information including step templates, configuration, and dependency graph.

**Parameters**:
- `namespace` (path) - The namespace name
- `name` (path) - The handler name
- `version` (query, optional) - Specific version to retrieve (defaults to latest)

**Example Request**:
```bash
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     https://your-app.com/tasker/handlers/payments/process_payment?version=2.1.0
```

**Example Response**:
```json
{
  "id": "process_payment",
  "namespace": "payments",
  "version": "2.1.0",
  "description": "Process customer payment with validation and confirmation",
  "step_templates": [
    {
      "name": "validate_payment",
      "description": "Validate payment details and customer information",
      "handler_class": "Payments::StepHandler::ValidatePaymentHandler",
      "depends_on_step": null,
      "default_retryable": false,
      "default_retry_limit": 0,
      "skippable": false,
      "custom_events": []
    },
    {
      "name": "charge_card",
      "description": "Process payment through payment gateway",
      "handler_class": "Payments::StepHandler::ChargeCardHandler",
      "depends_on_step": "validate_payment",
      "default_retryable": true,
      "default_retry_limit": 3,
      "skippable": false,
      "custom_events": ["payment.gateway.charged"]
    },
    {
      "name": "update_order",
      "description": "Update order status after successful payment",
      "handler_class": "Payments::StepHandler::UpdateOrderHandler",
      "depends_on_step": "charge_card",
      "default_retryable": true,
      "default_retry_limit": 2,
      "skippable": false,
      "custom_events": []
    },
    {
      "name": "send_confirmation",
      "description": "Send payment confirmation email to customer",
      "handler_class": "Payments::StepHandler::SendConfirmationHandler",
      "depends_on_step": "update_order",
      "default_retryable": true,
      "default_retry_limit": 5,
      "skippable": true,
      "custom_events": ["notification.email.sent"]
    }
  ],
  "dependency_graph": {
    "nodes": ["validate_payment", "charge_card", "update_order", "send_confirmation"],
    "edges": [
      {"from": "validate_payment", "to": "charge_card"},
      {"from": "charge_card", "to": "update_order"},
      {"from": "update_order", "to": "send_confirmation"}
    ],
    "execution_order": ["validate_payment", "charge_card", "update_order", "send_confirmation"]
  }
}
```

## Task Management API

The task management API supports creating and managing tasks with full namespace and version support.

### Create Task

**Endpoint**: `POST /tasker/tasks`

**Description**: Creates a new task with namespace and version support.

**Request Body**:
```json
{
  "name": "process_payment",
  "namespace": "payments",
  "version": "2.1.0",
  "context": {
    "payment_id": 12345,
    "amount": 99.99,
    "currency": "USD",
    "customer_id": 67890
  }
}
```

**Example Request**:
```bash
curl -X POST -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "process_payment",
       "namespace": "payments",
       "version": "2.1.0",
       "context": {
         "payment_id": 12345,
         "amount": 99.99,
         "currency": "USD",
         "customer_id": 67890
       }
     }' \
     https://your-app.com/tasker/tasks
```

**Example Response**:
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "process_payment",
  "namespace": "payments",
  "version": "2.1.0",
  "full_name": "payments.process_payment@2.1.0",
  "status": "pending",
  "context": {
    "payment_id": 12345,
    "amount": 99.99,
    "currency": "USD",
    "customer_id": 67890
  },
  "created_at": "2024-01-15T10:30:00Z",
  "updated_at": "2024-01-15T10:30:00Z"
}
```

### List Tasks

**Endpoint**: `GET /tasker/tasks`

**Description**: Lists tasks with optional filtering by namespace, version, and status.

**Query Parameters**:
- `namespace` (optional) - Filter by namespace
- `version` (optional) - Filter by version
- `status` (optional) - Filter by task status
- `page` (optional) - Page number for pagination
- `per_page` (optional) - Items per page (default: 25, max: 100)

**Example Request**:
```bash
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     "https://your-app.com/tasker/tasks?namespace=payments&version=2.1.0&status=pending&page=1&per_page=10"
```

**Example Response**:
```json
{
  "tasks": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "process_payment",
      "namespace": "payments",
      "version": "2.1.0",
      "full_name": "payments.process_payment@2.1.0",
      "status": "pending",
      "context": {...},
      "created_at": "2024-01-15T10:30:00Z",
      "updated_at": "2024-01-15T10:30:00Z"
    }
  ],
  "pagination": {
    "current_page": 1,
    "per_page": 10,
    "total_pages": 5,
    "total_count": 42
  }
}
```

### Get Task Details

**Endpoint**: `GET /tasker/tasks/{id}`

**Description**: Returns detailed information about a specific task.

**Parameters**:
- `id` (path) - The task ID
- `include_dependencies` (query, optional) - Include dependency graph analysis

**Example Request**:
```bash
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     https://your-app.com/tasker/tasks/550e8400-e29b-41d4-a716-446655440000?include_dependencies=true
```

**Example Response**:
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "process_payment",
  "namespace": "payments",
  "version": "2.1.0",
  "full_name": "payments.process_payment@2.1.0",
  "status": "in_progress",
  "context": {
    "payment_id": 12345,
    "amount": 99.99,
    "currency": "USD",
    "customer_id": 67890
  },
  "steps": [
    {
      "name": "validate_payment",
      "status": "complete",
      "results": {"valid": true, "validation_id": "val_123"},
      "attempts": 1,
      "started_at": "2024-01-15T10:30:05Z",
      "completed_at": "2024-01-15T10:30:06Z"
    },
    {
      "name": "charge_card",
      "status": "in_progress",
      "results": null,
      "attempts": 1,
      "started_at": "2024-01-15T10:30:07Z",
      "completed_at": null
    }
  ],
  "dependencies": {
    "analysis": "Task is progressing normally through dependency chain",
    "blocked_steps": [],
    "ready_steps": ["charge_card"],
    "completed_steps": ["validate_payment"]
  },
  "created_at": "2024-01-15T10:30:00Z",
  "updated_at": "2024-01-15T10:30:07Z"
}
```

## Error Handling

The API uses standard HTTP status codes and provides detailed error information:

### HTTP Status Codes

- `200 OK` - Successful request
- `201 Created` - Resource created successfully
- `400 Bad Request` - Invalid request parameters
- `401 Unauthorized` - Authentication required
- `403 Forbidden` - Insufficient permissions
- `404 Not Found` - Resource not found
- `422 Unprocessable Entity` - Validation errors
- `500 Internal Server Error` - Server error

### Error Response Format

```json
{
  "error": {
    "type": "ValidationError",
    "message": "Invalid task configuration",
    "details": {
      "namespace": ["must be present"],
      "version": ["must be a valid semantic version"]
    },
    "code": "INVALID_TASK_CONFIG"
  }
}
```

### Common Error Scenarios

**Handler Not Found**:
```json
{
  "error": {
    "type": "HandlerNotFound",
    "message": "Handler 'unknown_handler' not found in namespace 'payments' version '1.0.0'",
    "code": "HANDLER_NOT_FOUND"
  }
}
```

**Namespace Not Found**:
```json
{
  "error": {
    "type": "NamespaceNotFound",
    "message": "Namespace 'unknown_namespace' does not exist",
    "code": "NAMESPACE_NOT_FOUND"
  }
}
```

**Authentication Error**:
```json
{
  "error": {
    "type": "AuthenticationError",
    "message": "Invalid or expired authentication token",
    "code": "AUTHENTICATION_FAILED"
  }
}
```

**Authorization Error**:
```json
{
  "error": {
    "type": "AuthorizationError",
    "message": "Insufficient permissions for tasker.handler:index",
    "code": "AUTHORIZATION_FAILED"
  }
}
```

## Rate Limiting

The API respects standard Rails rate limiting configurations. Consider implementing rate limiting for production deployments:

```ruby
# config/initializers/rack_attack.rb
Rack::Attack.throttle('tasker-api', limit: 100, period: 1.minute) do |req|
  req.ip if req.path.start_with?('/tasker/')
end
```

## OpenAPI/Swagger Documentation

Tasker automatically generates OpenAPI documentation for all endpoints. The API documentation is available at:

- **Swagger UI**: `https://your-app.com/tasker/api-docs`
- **OpenAPI Spec**: `https://your-app.com/tasker/api-docs.json`

The documentation includes:
- Complete endpoint specifications
- Request/response schemas
- Authentication requirements
- Error response formats
- Interactive API testing interface

## SDK and Client Libraries

### cURL Examples

**Complete Handler Discovery Workflow**:
```bash
# 1. List all namespaces
curl -H "Authorization: Bearer $TOKEN" \
     https://your-app.com/tasker/handlers

# 2. Explore handlers in payments namespace
curl -H "Authorization: Bearer $TOKEN" \
     https://your-app.com/tasker/handlers/payments

# 3. Get detailed handler information with dependency graph
curl -H "Authorization: Bearer $TOKEN" \
     https://your-app.com/tasker/handlers/payments/process_payment?version=2.1.0

# 4. Create a task using discovered handler
curl -X POST -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"name": "process_payment", "namespace": "payments", "version": "2.1.0", "context": {"payment_id": 123}}' \
     https://your-app.com/tasker/tasks

# 5. Monitor task progress
curl -H "Authorization: Bearer $TOKEN" \
     https://your-app.com/tasker/tasks/TASK_ID?include_dependencies=true
```

### JavaScript/Node.js Example

```javascript
const axios = require('axios');

class TaskerClient {
  constructor(baseURL, token) {
    this.client = axios.create({
      baseURL,
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      }
    });
  }

  async getNamespaces() {
    const response = await this.client.get('/handlers');
    return response.data.namespaces;
  }

  async getHandlers(namespace) {
    const response = await this.client.get(`/handlers/${namespace}`);
    return response.data.handlers;
  }

  async getHandlerDetails(namespace, name, version = null) {
    const params = version ? { version } : {};
    const response = await this.client.get(`/handlers/${namespace}/${name}`, { params });
    return response.data;
  }

  async createTask(name, namespace, version, context) {
    const response = await this.client.post('/tasks', {
      name, namespace, version, context
    });
    return response.data;
  }

  async getTask(id, includeDependencies = false) {
    const params = includeDependencies ? { include_dependencies: true } : {};
    const response = await this.client.get(`/tasks/${id}`, { params });
    return response.data;
  }
}

// Usage
const tasker = new TaskerClient('https://your-app.com/tasker', 'YOUR_JWT_TOKEN');

// Discover and create task
const namespaces = await tasker.getNamespaces();
const handlers = await tasker.getHandlers('payments');
const handlerDetails = await tasker.getHandlerDetails('payments', 'process_payment', '2.1.0');
const task = await tasker.createTask('process_payment', 'payments', '2.1.0', { payment_id: 123 });
```

## Best Practices

### 1. Version Management
- Always specify versions in production integrations
- Use semantic versioning for handler versions
- Test version compatibility before deployment

### 2. Error Handling
- Implement proper error handling for all API calls
- Use exponential backoff for retryable errors
- Log API errors for monitoring and debugging

### 3. Authentication
- Use secure token storage and rotation
- Implement proper token refresh mechanisms
- Never log authentication tokens

### 4. Performance
- Use pagination for large result sets
- Cache handler discovery results when appropriate
- Monitor API response times and implement timeouts

### 5. Monitoring
- Track API usage and performance metrics
- Set up alerts for error rates and response times
- Monitor task creation and completion rates

## Integration Examples

### CI/CD Pipeline Integration

```yaml
# .github/workflows/deploy.yml
- name: Validate Handlers
  run: |
    # Validate all handlers are accessible via API
    curl -f -H "Authorization: Bearer $TASKER_TOKEN" \
         https://your-app.com/tasker/handlers/payments/process_payment?version=2.1.0
```

### Monitoring Dashboard Integration

```javascript
// Monitor task creation and handler usage
const monitorTasks = async () => {
  const tasks = await tasker.client.get('/tasks?status=pending&per_page=100');
  const metrics = {
    pending_tasks: tasks.data.pagination.total_count,
    namespaces: new Set(tasks.data.tasks.map(t => t.namespace)).size
  };

  // Send to monitoring system
  await sendMetrics(metrics);
};
```

### Load Testing

```javascript
// Load test handler discovery API
const loadTestHandlers = async () => {
  const promises = [];
  for (let i = 0; i < 100; i++) {
    promises.push(tasker.getHandlerDetails('payments', 'process_payment'));
  }

  const results = await Promise.allSettled(promises);
  const successful = results.filter(r => r.status === 'fulfilled').length;
  console.log(`${successful}/100 requests successful`);
};
```

---

This REST API provides comprehensive access to Tasker's handler discovery and task management capabilities, enabling enterprise-scale workflow orchestration with full namespace and version support.
