# Tasker Health Monitoring Guide

## Overview

Tasker provides enterprise-grade health monitoring endpoints designed for production deployments, Kubernetes environments, and load balancer health checks. The system offers three distinct endpoints optimized for different monitoring scenarios with optional authentication and authorization.

## 🎯 Health Endpoints

### 1. Readiness Probe - `/tasker/health/ready`

**Purpose**: Kubernetes readiness probe and deep health validation
**Performance**: < 100ms response time with comprehensive checks
**Authentication**: Never required (K8s compatibility)
**Authorization**: Never required (K8s compatibility)

```bash
GET /tasker/health/ready
```

**Response Format**:
```json
{
  "ready": true,
  "checks": {
    "database": { "status": "ok", "response_time_ms": 12 },
    "migrations": { "status": "ok" },
    "configuration": { "status": "ok" }
  },
  "timestamp": "2025-06-18T15:30:00Z"
}
```

**Use Cases**:
- Kubernetes readiness probes
- Load balancer health checks
- Deployment validation
- Service mesh health validation

### 2. Liveness Probe - `/tasker/health/live`

**Purpose**: Kubernetes liveness probe and basic availability check
**Performance**: < 10ms response time (minimal processing)
**Authentication**: Never required (K8s compatibility)
**Authorization**: Never required (K8s compatibility)

```bash
GET /tasker/health/live
```

**Response Format**:
```json
{
  "alive": true,
  "timestamp": "2025-06-18T15:30:00Z"
}
```

**Use Cases**:
- Kubernetes liveness probes
- Basic availability monitoring
- Circuit breaker health checks
- Minimal overhead health validation

### 3. Status Endpoint - `/tasker/health/status`

**Purpose**: Comprehensive system status and metrics
**Performance**: < 100ms response time with 15-second caching
**Authentication**: Configurable (optional)
**Authorization**: Uses `tasker.health_status:index` permission

```bash
GET /tasker/health/status
```

**Response Format**:
```json
{
  "status": "healthy",
  "system_health": {
    "overall_status": "healthy",
    "total_tasks": 1250,
    "pending_tasks": 45,
    "running_tasks": 12,
    "completed_tasks": 1180,
    "failed_tasks": 13,
    "blocked_tasks": 0,
    "retry_queue_size": 3
  },
  "performance_metrics": {
    "avg_task_completion_time_ms": 2340,
    "avg_step_completion_time_ms": 450,
    "retry_success_rate": 0.87
  },
  "timestamp": "2025-06-18T15:30:00Z",
  "cache_info": {
    "cached": true,
    "cache_expires_at": "2025-06-18T15:30:15Z"
  }
}
```

**Use Cases**:
- Monitoring dashboards
- Alerting systems
- Performance analysis
- Capacity planning

## 🔒 Security Configuration

### Authentication Configuration

Control authentication requirements for the status endpoint:

```ruby
# config/initializers/tasker.rb
Tasker.configuration do |config|
  config.health do |health|
    # Optional authentication for status endpoint
    health.status_requires_authentication = true  # Default: false

    # Cache duration for status endpoint (seconds)
    health.cache_duration_seconds = 15  # Default: 15
  end
end
```

**Important Notes**:
- Ready and live endpoints **never** require authentication (K8s compatibility)
- Only the status endpoint can optionally require authentication
- Authentication uses your configured authenticator class

### Authorization Configuration

Enable fine-grained authorization for the status endpoint:

```ruby
# config/initializers/tasker.rb
Tasker.configuration do |config|
  config.auth do |auth|
    auth.authorization_enabled = true
    auth.authorization_coordinator_class = 'YourAuthorizationCoordinator'
  end
end
```

**Permission Model**: `tasker.health_status:index`
- **Resource**: `tasker.health_status` (specific to status endpoint)
- **Action**: `index` (standard CRUD action for viewing)
- **Full Permission**: `tasker.health_status:index`

### Authorization Coordinator Implementation

```ruby
# app/tasker/authorization/your_authorization_coordinator.rb
class YourAuthorizationCoordinator < Tasker::Authorization::BaseCoordinator
  include Tasker::Authorization::ResourceConstants

  protected

  def authorized?(resource, action, context = {})
    case resource
    when RESOURCES::HEALTH_STATUS
      authorize_health_status_action(action, context)
    # ... other resources
    else
      false
    end
  end

  private

  def authorize_health_status_action(action, _context)
    return false unless user.respond_to?(:has_tasker_permission?)

    case action
    when :index
      # Admin users always have access
      user.tasker_admin? ||
        # Regular users need explicit permission
        user.has_tasker_permission?("#{RESOURCES::HEALTH_STATUS}:#{action}")
    else
      false
    end
  end
end
```

## 🚀 Production Deployment

### Kubernetes Configuration

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: your-app
spec:
  template:
    spec:
      containers:
      - name: app
        image: your-app:latest
        ports:
        - containerPort: 3000

        # Readiness probe - comprehensive health check
        readinessProbe:
          httpGet:
            path: /tasker/health/ready
            port: 3000
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3

        # Liveness probe - basic availability check
        livenessProbe:
          httpGet:
            path: /tasker/health/live
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 1
          failureThreshold: 3
```

### Load Balancer Configuration

**NGINX**:
```nginx
upstream tasker_app {
    server app1:3000;
    server app2:3000;
}

# Health check configuration
location /health {
    access_log off;
    proxy_pass http://tasker_app/tasker/health/ready;
    proxy_set_header Host $host;
}
```

**HAProxy**:
```
backend tasker_servers
    balance roundrobin
    option httpchk GET /tasker/health/ready
    server app1 app1:3000 check
    server app2 app2:3000 check
```

### Docker Health Checks

```dockerfile
# Dockerfile
FROM ruby:3.2

# ... your app setup ...

# Health check using liveness endpoint
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3000/tasker/health/live || exit 1
```

## 📊 Monitoring Integration

### Prometheus Metrics

Create a custom exporter using the status endpoint:

```ruby
# lib/prometheus_tasker_exporter.rb
class PrometheusTaskerExporter
  def self.collect_metrics
    response = HTTParty.get("#{Rails.application.routes.url_helpers.root_url}tasker/health/status")
    health_data = JSON.parse(response.body)

    # Export metrics to Prometheus
    {
      tasker_total_tasks: health_data.dig('system_health', 'total_tasks'),
      tasker_pending_tasks: health_data.dig('system_health', 'pending_tasks'),
      tasker_failed_tasks: health_data.dig('system_health', 'failed_tasks'),
      tasker_avg_completion_time: health_data.dig('performance_metrics', 'avg_task_completion_time_ms')
    }
  end
end
```

### Datadog Integration

```ruby
# config/initializers/datadog_tasker.rb
if Rails.env.production?
  Thread.new do
    loop do
      begin
        response = HTTParty.get("http://localhost:3000/tasker/health/status")
        health_data = JSON.parse(response.body)

        Datadog::Statsd.new.batch do |s|
          s.gauge('tasker.tasks.total', health_data.dig('system_health', 'total_tasks'))
          s.gauge('tasker.tasks.pending', health_data.dig('system_health', 'pending_tasks'))
          s.gauge('tasker.tasks.failed', health_data.dig('system_health', 'failed_tasks'))
          s.gauge('tasker.performance.avg_completion_time',
                  health_data.dig('performance_metrics', 'avg_task_completion_time_ms'))
        end
      rescue => e
        Rails.logger.error "Tasker health metrics error: #{e.message}"
      end

      sleep 30  # Collect every 30 seconds
    end
  end
end
```

### Alerting Examples

**PagerDuty Integration**:
```ruby
# lib/tasker_health_monitor.rb
class TaskerHealthMonitor
  def self.check_and_alert
    response = HTTParty.get("http://localhost:3000/tasker/health/status")
    health_data = JSON.parse(response.body)

    failed_tasks = health_data.dig('system_health', 'failed_tasks')
    total_tasks = health_data.dig('system_health', 'total_tasks')

    # Alert if failure rate > 5%
    if total_tasks > 0 && (failed_tasks.to_f / total_tasks) > 0.05
      PagerDuty.trigger_incident(
        summary: "Tasker failure rate exceeded 5%",
        details: health_data
      )
    end
  end
end
```

## 🔧 Configuration Options

### Health Configuration

```ruby
# config/initializers/tasker.rb
Tasker.configuration do |config|
  config.health do |health|
    # Authentication requirement for status endpoint
    health.status_requires_authentication = false  # Default: false

    # Cache duration for status endpoint responses
    health.cache_duration_seconds = 15  # Default: 15 seconds
  end
end
```

### Performance Tuning

**Database Connection Optimization**:
```ruby
# config/database.yml
production:
  # ... existing config ...

  # Optimize for health check queries
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  checkout_timeout: 5

  # Health check specific optimizations
  prepared_statements: true
  advisory_locks: false
```

**Cache Configuration**:
```ruby
# config/environments/production.rb
Rails.application.configure do
  # Use Redis for health check caching
  config.cache_store = :redis_cache_store, {
    url: ENV['REDIS_URL'],
    namespace: 'tasker_health',
    expires_in: 15.seconds
  }
end
```

## 🧪 Testing Health Endpoints

### RSpec Testing

```ruby
# spec/requests/health_spec.rb
RSpec.describe 'Health Endpoints', type: :request do
  describe 'GET /tasker/health/ready' do
    it 'returns ready status' do
      get '/tasker/health/ready'

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['ready']).to be true
      expect(json['checks']).to be_present
    end
  end

  describe 'GET /tasker/health/live' do
    it 'returns alive status' do
      get '/tasker/health/live'

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['alive']).to be true
    end
  end

  describe 'GET /tasker/health/status' do
    context 'with authorization disabled' do
      it 'returns comprehensive status' do
        get '/tasker/health/status'

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['status']).to be_present
        expect(json['system_health']).to be_present
      end
    end

    context 'with authorization enabled' do
      before do
        # Configure authorization for testing
        Tasker.configure do |config|
          config.auth.authorization_enabled = true
          config.auth.authorization_coordinator_class = 'TestAuthorizationCoordinator'
        end
      end

      it 'requires health_status.index permission' do
        get '/tasker/health/status'
        expect(response).to have_http_status(:forbidden)
      end

      it 'allows access with proper permission' do
        # Mock authenticated user with permission
        allow_any_instance_of(TestAuthenticator)
          .to receive(:current_user)
          .and_return(user_with_permission('tasker.health_status:index'))

        get '/tasker/health/status', headers: auth_headers
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
```

### Load Testing

```bash
# Basic load test for health endpoints
ab -n 1000 -c 10 http://localhost:3000/tasker/health/ready
ab -n 1000 -c 10 http://localhost:3000/tasker/health/live
ab -n 1000 -c 10 http://localhost:3000/tasker/health/status
```

## 🚨 Troubleshooting

### Common Issues

**1. Slow Health Check Responses**

```ruby
# Check database connection pool
ActiveRecord::Base.connection_pool.stat
# => {:size=>5, :connections=>5, :busy=>2, :dead=>0, :idle=>3, :waiting=>0, :checkout_timeout=>5.0}

# If waiting > 0, increase pool size or reduce checkout_timeout
```

**2. Cache Not Working**

```ruby
# Verify cache configuration
Rails.cache.write('test_key', 'test_value')
Rails.cache.read('test_key')  # Should return 'test_value'

# Check cache store configuration
Rails.application.config.cache_store
```

**3. Authorization Errors**

```ruby
# Debug authorization coordinator
coordinator = YourAuthorizationCoordinator.new(current_user)
coordinator.authorize!('tasker.health_status', :index)
# Should not raise an error for authorized users
```

### Health Check Debugging

```ruby
# Add to your health controller for debugging
class HealthController < Tasker::HealthController
  private

  def debug_health_info
    Rails.logger.info "Health check requested by #{request.remote_ip}"
    Rails.logger.info "Database connections: #{ActiveRecord::Base.connection_pool.stat}"
    Rails.logger.info "Cache store: #{Rails.cache.class.name}"
  end
end
```

## 📈 Performance Benchmarks

### Typical Response Times

| Endpoint | Cached | Uncached | Database Load |
|----------|--------|----------|---------------|
| `/ready` | N/A | 50-80ms | Medium |
| `/live` | N/A | 5-10ms | None |
| `/status` | 10-15ms | 80-120ms | High |

### Optimization Tips

1. **Use Redis / Memcached / Cloud provider** - 5x faster than database cache
2. **Optimize database queries** - Use connection pooling
3. **Monitor response times** - Set up alerts for > 200ms responses
4. **Use CDN for static health responses** - For geographically distributed deployments

## 🔗 Related Documentation

- **[Authentication & Authorization](AUTH.md)** - Complete security system
- **[SQL Functions](SQL_FUNCTIONS.md)** - High-performance database functions
- **[Configuration](OVERVIEW.md)** - System configuration options
- **[Troubleshooting](TROUBLESHOOTING.md)** - Common issues and solutions

---

**Tasker Health Monitoring** provides enterprise-grade health endpoints optimized for production deployments, Kubernetes environments, and comprehensive system monitoring.
