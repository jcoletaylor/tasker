# Technical Context: Tasker Engine 1.0.0

## Core Technology Stack

### Rails Engine Foundation
- **Rails 7+**: Modern Rails framework with latest features
- **Ruby 3.2+**: Performance and syntax improvements
- **PostgreSQL**: Primary database with advanced features
- **Redis**: Caching and session management

### Key Dependencies
- **Dry-rb Ecosystem**: Type validation and functional programming patterns
- **Statesman**: State machine implementation for workflow steps
- **GraphQL**: Modern API interface alongside REST
- **OpenTelemetry**: Comprehensive observability and tracing

### Development & Testing
- **RSpec**: Primary testing framework with comprehensive coverage
- **FactoryBot**: Test data generation
- **SimpleCov**: Code coverage tracking
- **Standard**: Ruby style guide enforcement

## Blog Validation Framework Architecture

### PORO-Based Model Strategy ✅
**Challenge Solved**: Blog example models conflicted with Tasker's ActiveRecord models (enum method collisions)

**Solution**: Plain Old Ruby Objects with ActiveModel concerns
```ruby
# Blog Models (No ActiveRecord, No Conflicts)
module BlogExamples
  module Post01
    class Order
      include ActiveModel::Model
      include ActiveModel::Attributes
      include ActiveModel::Validations

      # Attributes with type safety
      attribute :status, :string, default: 'pending'
      attribute :total_amount, :decimal
      attribute :customer_email, :string

      # Manual status methods (no enum conflicts)
      def pending?
        status == 'pending'
      end

      def confirmed?
        status == 'confirmed'
      end

      # Full validation support
      validates :customer_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
      validates :total_amount, presence: true, numericality: { greater_than: 0 }
    end
  end
end
```

**Benefits**:
- **Zero Conflicts**: No method collisions with Tasker's ActiveRecord models
- **Full Validation**: ActiveModel provides complete validation capabilities
- **Type Safety**: ActiveModel::Attributes provides type coercion
- **Namespace Isolation**: Blog code completely isolated from Tasker internals
- **CI Compatible**: No external dependencies, works in all environments

### Mock Service Architecture
**Pattern**: Configurable mock services with call logging and failure simulation
```ruby
class MockPaymentService < BaseMockService
  def charge(amount:, token:, **options)
    simulate_call_delay

    if should_fail?
      raise PaymentError, failure_message
    end

    {
      payment_id: generate_payment_id,
      amount_charged: amount,
      transaction_id: SecureRandom.hex(8)
    }
  end
end
```

### Fixture-Based Code Loading
**Strategy**: Copy blog code to repository fixtures for CI reliability
```ruby
def load_blog_code(post_name, file_path)
  fixtures_root = File.join(File.dirname(__FILE__), '..', 'fixtures')
  full_path = File.join(fixtures_root, post_name, file_path)
  load full_path  # Use 'load' for reloadability
end
```

## Database Architecture

### Core Schema Design
- **Polymorphic Relationships**: Flexible associations for different task types
- **JSON Columns**: Complex data storage with PostgreSQL features
- **Function-Based Analytics**: SQL functions for high-performance queries
- **Event Sourcing**: Complete audit trail for workflow execution

### Performance Optimizations
- **Materialized Views**: Pre-computed analytics and reporting data
- **Selective Indexing**: Optimized for common query patterns
- **Connection Pooling**: Intelligent connection management
- **Query Optimization**: Function-based analytics reduce N+1 queries

## Security Architecture

### Authentication Framework
- **Pluggable Authentication**: Support for various auth providers
- **JWT Integration**: Stateless authentication for API access
- **Session Management**: Secure session handling with Redis

### Authorization System
- **Policy-Based**: Declarative authorization rules
- **Resource-Level**: Fine-grained permissions for tasks and workflows
- **Coordinator Pattern**: Centralized authorization logic

## Observability & Monitoring

### Telemetry Integration
- **OpenTelemetry**: Distributed tracing and metrics
- **Custom Metrics**: Workflow-specific performance tracking
- **Error Tracking**: Comprehensive error reporting and alerting
- **Performance Monitoring**: Database query optimization and bottleneck detection

### Event System
- **Lifecycle Events**: Complete workflow execution tracking
- **Custom Events**: User-defined event publishing
- **Subscriber Framework**: Flexible event handling and integration
- **Metrics Export**: Automated performance data collection

## Development Patterns

### Code Generation
- **Rails Generators**: Automated scaffolding for common patterns
- **Template System**: Consistent project structure and configuration
- **Best Practices**: Built-in patterns for security and performance

### Testing Strategy
- **Unit Testing**: Comprehensive component testing with RSpec
- **Integration Testing**: End-to-end workflow validation
- **Mock Services**: Isolated testing of external dependencies
- **Blog Validation**: Automated testing of documentation examples

## Deployment & Operations

### Container Strategy
- **Docker Support**: Production-ready containerization
- **Kubernetes Manifests**: Scalable deployment patterns
- **Health Checks**: Comprehensive readiness and liveness probes
- **Resource Management**: Optimized resource allocation

### Configuration Management
- **Environment-Based**: Separate configuration for each deployment environment
- **Secret Management**: Secure handling of sensitive configuration
- **Feature Flags**: Runtime configuration for gradual rollouts
- **Monitoring Integration**: Automated alerting and incident response

## Future Technology Roadmap

### Short Term (Next 6 Months)
- **GraphQL Subscriptions**: Real-time workflow updates
- **Advanced Analytics**: Machine learning for workflow optimization
- **Enhanced Security**: Advanced threat detection and prevention

### Medium Term (6-12 Months)
- **Multi-Tenant**: Support for isolated tenant environments
- **Workflow Versioning**: Schema evolution and backward compatibility
- **Advanced Integrations**: Deep integration with popular Rails gems

### Long Term (12+ Months)
- **Distributed Workflows**: Cross-service workflow coordination
- **AI-Powered Optimization**: Intelligent workflow tuning
- **Enterprise Features**: Advanced compliance and governance tools
