# Post 04: Team Scaling - "When Team Growth Became a Namespace War"

## Overview

This example demonstrates how Tasker enables teams to scale independently while maintaining coordination through well-defined interfaces. The key innovation is **cross-system coordination** - one team's workflow can delegate to another team's Tasker system through the standard task interface.

## Key Patterns Demonstrated

### 1. Cross-System Coordination Innovation

The `ExecuteRefundWorkflowHandler` demonstrates a breakthrough pattern: **Tasker-to-Tasker communication**. Instead of teams building custom integration points, they can delegate to other teams' Tasker systems using the standard `/tasker/tasks` endpoint.

#### How It Works:
- Customer Success team needs to execute a refund
- Instead of duplicating payment logic, they delegate to the Payments team's Tasker system
- The delegation happens through a standard HTTP POST to `/tasker/tasks`
- The response confirms task creation (not execution) since all Tasker systems are asynchronous

#### Technical Details:
```ruby
# POST /tasker/tasks
{
  namespace: 'payments',
  workflow_name: 'process_refund',
  workflow_version: '2.1.0',
  context: { ... }
}

# Response (task creation confirmation):
{
  task_id: 'task_123',
  status: 'queued', # or 'created'
  namespace: 'payments',
  workflow_name: 'process_refund'
}
```

#### Key Insight:
- We validate **task creation success**, not task execution results
- The remote Tasker system handles execution asynchronously
- This treats other Tasker systems as standard API endpoints
- Teams maintain independence while enabling coordination

### 2. Mock Service Isolation

Several step handlers use mock services to isolate concerns:

#### Pattern:
```ruby
# Instead of direct HTTP introspection:
response = connection.post('/api/endpoint', data)
case response.status
when 200...

# We use service wrappers:
result = MockPaymentGateway.process_refund(data)
# Service wrapper handles HTTP details and error classification
```

#### Benefits:
- **Separation of Concerns**: Step handlers focus on business logic
- **Testability**: Mock services provide consistent test behavior
- **Maintainability**: HTTP details isolated in service layer
- **Reusability**: Service wrappers can be shared across handlers

#### Mock Services Used:
- `MockPaymentGateway` - Payment processing operations
- `MockCustomerServiceSystem` - Customer service platform integration
- `MockRefundPolicyService` - Policy evaluation logic
- `MockManagerApprovalSystem` - Human approval workflows

### 3. Namespace Isolation

Two teams implement the same logical workflow (`process_refund`) with different:
- **Business Logic**: Direct gateway vs approval-based
- **Data Models**: Different field names and structures
- **Versions**: payments v2.1.0 vs customer_success v1.3.0
- **Authorization**: Role-based access control

## Architecture Benefits

### Team Independence
- Teams can evolve their workflows independently
- Different versioning strategies per team
- Separate deployment cycles
- Team-specific business logic

### System Coordination
- Standard interfaces for cross-team communication
- Asynchronous delegation prevents tight coupling
- Correlation IDs for cross-system tracking
- Consistent error handling patterns

### Operational Excellence
- Each team owns their domain expertise
- Shared infrastructure (Tasker) with team-specific implementations
- Clear audit trails across team boundaries
- Scalable coordination patterns

## Implementation Notes

### Cross-System Communication
When delegating to another Tasker system:
1. **Use Standard Endpoint**: Always POST to `/tasker/tasks`
2. **Expect Task Creation Response**: Validate task was queued, not executed
3. **Handle Asynchronously**: Don't wait for execution results
4. **Include Correlation IDs**: Enable cross-system tracking

### Correlation IDs: Cross-System Observability

One of the most powerful aspects of the cross-system coordination pattern is **distributed tracing through correlation IDs**. This enables complete visibility across team boundaries.

#### How Correlation IDs Work

```ruby
# Customer Success generates correlation ID
correlation_id = normalized_context[:correlation_id] || generate_correlation_id

# Include in cross-system request
context: {
  payment_id: 'pay_123',
  correlation_id: 'cs-abc123def456',  # Tracks across systems
  initiated_by: 'customer_success'
}
```

#### Observability Benefits

1. **End-to-End Tracing**: Follow a single customer request across multiple teams
   - Customer Success → Payments → Gateway → Records → Notifications
   - Each step logs the same correlation ID

2. **Cross-Team Debugging**: When something fails, both teams can search logs
   ```bash
   # Customer Success team searches their logs
   grep "cs-abc123def456" customer-success.log

   # Payments team searches their logs
   grep "cs-abc123def456" payments.log
   ```

3. **Performance Analysis**: Measure end-to-end latency across teams
   - How long from customer request to payment completion?
   - Which team's steps are the bottleneck?

4. **Business Process Visibility**: Track complex workflows
   - Refund approval → Payment processing → Customer notification
   - Cross-reference with business metrics and SLAs

#### Implementation Pattern

```ruby
def generate_correlation_id
  # Team prefix enables quick identification of origin
  "cs-#{SecureRandom.hex(8)}"  # Customer Success prefix
end

# Each team can add their own prefix while preserving original
def enrich_correlation_id(original_id)
  "pay-#{original_id}"  # Payments team adds their prefix
end
```

#### Real-World Impact

- **Incident Response**: Quickly trace failures across team boundaries
- **Performance Monitoring**: Identify bottlenecks in cross-team workflows
- **Compliance Auditing**: Complete audit trail for regulatory requirements
- **Team Coordination**: Shared visibility reduces finger-pointing during issues

This transforms cross-team workflows from black boxes into fully observable, traceable processes.

### Mock Service Integration
When using mock services:
1. **Trust Service Layer**: Let service wrappers handle HTTP details
2. **Focus on Business Logic**: Step handlers orchestrate, don't introspect
3. **Consistent Error Classification**: Services should raise appropriate Tasker errors
4. **Test Isolation**: Mock services provide predictable test behavior

### Mixed Integration Patterns

This example demonstrates two valid integration approaches:

#### Pattern 1: Mock Service Isolation
**Used by:** `ValidateRefundRequestHandler`, `CheckRefundPolicyHandler`, `GetManagerApprovalHandler`, `ValidatePaymentEligibilityHandler`

```ruby
# Service wrapper handles HTTP details
result = MockPaymentGateway.process_refund(data)
# Service raises appropriate Tasker errors
```

**Benefits:**
- Clean separation of concerns
- Consistent error handling
- Easy testing and mocking
- Reusable service components

#### Pattern 2: Direct HTTP Integration
**Used by:** `UpdateTicketStatusHandler`, `ProcessGatewayRefundHandler`, `UpdatePaymentRecordsHandler`, `NotifyCustomerHandler`

```ruby
# Direct HTTP call with status introspection
response = connection.post('/api/endpoint', data)
case response.status
when 200
  # Handle success
when 400
  raise Tasker::PermanentError, 'Bad request'
# ... more status codes
end
```

**Benefits:**
- Full control over HTTP handling
- Explicit error classification
- No additional service layer
- Direct API integration

Both patterns are valid - choose based on your team's preferences and integration complexity.

## Real-World Application

This pattern solves common enterprise challenges:
- **Conway's Law**: System design reflects team structure
- **Microservice Coordination**: Teams need to work together without tight coupling
- **Domain Expertise**: Each team focuses on their strengths
- **Scaling Challenges**: Growth shouldn't create integration nightmares

The result is a system where team growth enhances capability rather than creating coordination problems.
