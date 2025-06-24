# Phase 4: Observability Enhancement - Implementation Plan

## ✅ **PHASE 4.1 SUCCESSFULLY COMPLETED** - Structured Logging System

### **Outstanding Implementation Results**
- **✅ Complete StructuredLogging Concern** - Enterprise-grade correlation ID management, JSON formatting, domain-specific helpers
- **✅ Comprehensive Integration** - Enhanced EventPublisher, WorkflowCoordinator, StepExecutor, TaskRunnerJob with structured logging
- **✅ Production-Ready Features** - Parameter filtering, performance monitoring, correlation ID propagation, structured exception handling
- **✅ 24/24 Tests Passing** - Complete test coverage with proper state management patterns
- **✅ Clean Architecture** - "Fail fast" philosophy, no defensive programming bloat

#### **Key Files Implemented**
```
✅ lib/tasker/concerns/structured_logging.rb          # Core logging concern with 12 methods
✅ lib/tasker/logging/correlation_id_generator.rb     # Enterprise-grade ID generation
✅ lib/tasker/concerns/event_publisher.rb             # Enhanced with logging integration
✅ lib/tasker/orchestration/workflow_coordinator.rb   # Performance monitoring added
✅ lib/tasker/orchestration/step_executor.rb          # Detailed step-level monitoring
✅ app/jobs/tasker/task_runner_job.rb                 # Background job observability
✅ spec/lib/tasker/concerns/structured_logging_spec.rb # 24 comprehensive tests
```

## Current State Analysis

### ✅ **Existing Strong Foundation (Enhanced)**
- **Comprehensive Event System**: Full event publishing with domain-specific helpers + **structured logging integration**
- **Structured Logging System**: **COMPLETE** - Correlation ID tracking, JSON formatting, performance monitoring
- **Event Catalog**: Well-organized event definitions across task, step, workflow, and observability domains
- **Telemetry Configuration**: Enhanced dry-struct configuration with observability parameters
- **Health Check System**: Basic health endpoints for production readiness
- **BaseSubscriber Infrastructure**: Complete foundation for event-driven metrics collection
- **Production-Ready Observability**: Comprehensive lifecycle logging with performance context

### 🎯 **Telemetry Architecture Strategy Analysis**
**Completed comprehensive analysis revealing:**

#### **Current Telemetry Gaps**
1. **Limited Trace Coverage** - TelemetrySubscriber handles only 8 events out of 40+ available lifecycle events
2. **Incomplete Span Hierarchy** - Only task→step spans, missing orchestration, batch execution, database operations
3. **No Native Metrics Collection** - Zero operational metrics for dashboards/alerting
4. **Event→Telemetry Mapping Inefficient** - Manual event handling vs leveraging robust pub/sub system

### 🚀 **Phase 4.2 Strategic Direction: Event-Driven Telemetry Architecture**
**Key Insight**: Leverage existing 40+ lifecycle events for comprehensive telemetry using intelligent event→telemetry routing

#### **Traces vs Metrics Decision Framework**
- **🔍 USE TRACES FOR**: Request-scoped operations, hierarchical operations, error debugging, performance investigation
- **📊 USE METRICS FOR**: Aggregate operational data, performance monitoring, health checks, alerting triggers

### 🎯 **Refined Implementation Priorities**
1. **Enhanced Telemetry Event Mapping**: Declarative event→telemetry routing using TelemetryEventRouter pattern
2. **Native Metrics Collection Backend**: Thread-safe metrics storage with Prometheus export
3. **Multi-Level Span Hierarchy**: 5+ level spans (task→orchestration→batch→steps) reflecting actual execution
4. **Additional Observability Events**: Surface missing lifecycle events for dependency resolution, backoff cycles, state transitions

## Implementation Strategy

### 📋 **Phase 4.1: Structured Logging System**
**Timeline**: 5-7 days
**Impact**: Critical - Production operations require correlation tracking

#### **Architecture Overview**
Build on existing event system to add structured logging with correlation IDs and performance context.

#### **Implementation Components**

##### **4.1.1 Correlation ID System**
```ruby
# lib/tasker/concerns/structured_logging.rb
module Tasker::Concerns::StructuredLogging
  extend ActiveSupport::Concern

  # Generate correlation ID for request/workflow tracking
  def correlation_id
    @correlation_id ||= generate_correlation_id
  end

  # Log with structured JSON format including correlation ID
  def log_structured(level, message, **context)
    structured_data = {
      timestamp: Time.current.iso8601,
      correlation_id: correlation_id,
      component: self.class.name,
      message: message,
      **context
    }

    # Apply parameter filtering
    filtered_data = apply_parameter_filtering(structured_data)

    Rails.logger.public_send(level, filtered_data.to_json)
  end
end
```

##### **4.1.2 Task/Step Logging Helpers**
```ruby
# Enhanced domain-specific logging methods
def log_task_event(task, event_type, **context)
  log_structured(:info, "Task #{event_type}",
    task_id: task.task_id,
    task_name: task.name,
    event_type: event_type,
    **context
  )
end

def log_step_event(step, event_type, duration: nil, **context)
  log_structured(:info, "Step #{event_type}",
    step_id: step.workflow_step_id,
    step_name: step.name,
    task_id: step.task.task_id,
    event_type: event_type,
    duration_ms: duration&.*(1000)&.round(2),
    **context
  )
end
```

##### **4.1.3 Integration Points**
- **Event Publisher Enhancement**: Add structured logging to all event publishing
- **Orchestration Components**: WorkflowCoordinator, StepExecutor, TaskFinalizer
- **Handler Integration**: Automatic logging in TaskHandler and StepHandler
- **Background Jobs**: TaskRunnerJob with correlation ID propagation

#### **Files to Create/Modify**
```
lib/tasker/concerns/structured_logging.rb          # New - Core logging concern
lib/tasker/logging/correlation_id_generator.rb     # New - ID generation logic
lib/tasker/logging/json_formatter.rb              # New - JSON log formatting
lib/tasker/logging/parameter_filter.rb            # New - Sensitive data filtering
lib/tasker/concerns/event_publisher.rb            # Enhanced - Add logging to events
lib/tasker/orchestration/workflow_coordinator.rb  # Enhanced - Add structured logging
lib/tasker/orchestration/step_executor.rb         # Enhanced - Add structured logging
spec/lib/tasker/concerns/structured_logging_spec.rb # New - Comprehensive tests
```

### 📊 **Phase 4.2: Native Metrics Collection Backend**
**Timeline**: 5-7 days
**Impact**: High - Essential for production monitoring

#### **Architecture Overview**
Build on existing metrics subscriber template to create a native metrics backend that integrates seamlessly with the current event system.

#### **Implementation Components**

##### **4.2.1 Native Metrics Storage**
```ruby
# lib/tasker/metrics/store.rb
module Tasker::Metrics
  class Store
    include Singleton

    def initialize
      @histograms = {}
      @counters = {}
      @gauges = {}
      @mutex = Mutex.new
    end

    # Thread-safe metric recording
    def record_histogram(name, value, tags = {})
      @mutex.synchronize do
        histogram = @histograms[name] ||= Histogram.new(name)
        histogram.observe(value, tags)
      end
    end

    def increment_counter(name, value = 1, tags = {})
      @mutex.synchronize do
        counter = @counters[name] ||= Counter.new(name)
        counter.increment(value, tags)
      end
    end

    def set_gauge(name, value, tags = {})
      @mutex.synchronize do
        gauge = @gauges[name] ||= Gauge.new(name)
        gauge.set(value, tags)
      end
    en

#### **Files to Create/Modify**
```
lib/tasker/metrics/store.rb                      # New - Thread-safe metrics storage
lib/tasker/metrics/histogram.rb                  # New - Histogram implementation
lib/tasker/metrics/counter.rb                    # New - Counter implementation
lib/tasker/metrics/gauge.rb                      # New - Gauge implementation
lib/tasker/metrics/core_subscriber.rb            # New - Event-based metrics collection
lib/tasker/metrics/prometheus_exporter.rb        # New - Prometheus format export
app/controllers/tasker/metrics_controller.rb     # New - Metrics endpoint
config/routes.rb                                 # Enhanced - Add metrics routes
lib/tasker/engine.rb                             # Enhanced - Initialize metrics
spec/lib/tasker/metrics/                         # New - Comprehensive metrics tests
```

---

## ✅ **PHASE 4.2.2.3.1 SUCCESSFULLY COMPLETED** - Plugin Architecture Integration Points

### **Outstanding Implementation Results**
- **✅ Event-Driven Export Coordination** - Complete ExportCoordinator with plugin registration and lifecycle events
- **✅ Plugin Registry System** - Centralized plugin discovery, format-based lookup, and auto-discovery capabilities
- **✅ BaseExporter Interface** - Abstract plugin class with lifecycle callbacks and error handling
- **✅ Built-in Format Exporters** - JSON and CSV exporters as reference implementations
- **✅ Comprehensive Testing** - 67+ tests covering plugin registration, event coordination, and format validation
- **✅ Framework Boundary Respect** - Clean separation between Tasker core and plugin responsibilities

#### **Developer-Facing Integration Points**

```ruby
# Plugin Development Example
class MyCustomExporter < Tasker::Telemetry::Plugins::BaseExporter
  VERSION = '1.0.0'
  DESCRIPTION = 'Custom metrics exporter for external system'

  def export(metrics_data, options = {})
    # Custom export logic
    response = HTTParty.post(@endpoint_url, {
      body: format_metrics(metrics_data).to_json
    })
    { success: response.success?, response: response }
  end

  def supports_format?(format)
    %w[json custom].include?(format.to_s)
  end

  # Optional lifecycle callbacks
  def on_cache_sync(sync_data)
    logger.info("Cache synced: #{sync_data[:metrics_count]} metrics")
  end
end

# Plugin Registration
coordinator = Tasker::Telemetry::ExportCoordinator.instance
coordinator.register_plugin('my_exporter', MyCustomExporter.new)
```

#### **Event Coordination System**
- **Export Events**: `CACHE_SYNCED`, `EXPORT_REQUESTED`, `EXPORT_COMPLETED`, `EXPORT_FAILED`
- **Plugin Events**: `PLUGIN_REGISTERED`, `PLUGIN_UNREGISTERED`
- **Lifecycle Integration**: Automatic coordination with MetricsBackend cache sync operations

---

## Real-World Telemetry Validation

### Overview
Comprehensive validation approaches for ensuring Tasker's telemetry and metrics exports correctly integrate with production observability systems including Jaeger and Prometheus.

### Local Development Environment Setup

#### Docker Compose for Observability Stack

```yaml
# docker-compose.observability.yml
version: '3.8'

services:
  jaeger:
    image: jaegertracing/all-in-one:1.47
    ports:
      - "16686:16686"    # Jaeger UI
      - "14250:14250"    # gRPC
      - "14268:14268"    # HTTP
    environment:
      - COLLECTOR_OTLP_ENABLED=true
    networks:
      - observability

  prometheus:
    image: prom/prometheus:v2.45.0
    ports:
      - "9090:9090"
    volumes:
      - ./config/prometheus.yml:/etc/prometheus/prometheus.yml
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=200h'
      - '--web.enable-lifecycle'
    networks:
      - observability

  grafana:
    image: grafana/grafana:10.0.0
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    networks:
      - observability

networks:
  observability:
    driver: bridge
```

#### Prometheus Configuration

```yaml
# config/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'tasker-metrics'
    static_configs:
      - targets: ['host.docker.internal:3000']  # Rails app
    metrics_path: '/tasker/metrics'
    scrape_interval: 30s
    scrape_timeout: 10s
```

### Validation Scripts

#### 1. Jaeger Trace Validation

```bash
#!/bin/bash
# scripts/validate_jaeger_traces.sh

JAEGER_URL="http://localhost:16686"
SERVICE_NAME="tasker"

echo "🔍 Validating Jaeger traces for Tasker..."

# Check Jaeger connectivity
curl -f "$JAEGER_URL/api/services" > /dev/null 2>&1 || {
    echo "❌ Jaeger not accessible"
    exit 1
}

# Get services and validate Tasker presence
SERVICES=$(curl -s "$JAEGER_URL/api/services" | jq -r '.data[]')
if echo "$SERVICES" | grep -q "$SERVICE_NAME"; then
    echo "✅ Tasker service found in Jaeger"
else
    echo "⚠️  Tasker service not found"
    exit 1
fi

# Analyze recent traces
TRACES=$(curl -s "$JAEGER_URL/api/traces?service=$SERVICE_NAME&lookback=1h")
TRACE_COUNT=$(echo "$TRACES" | jq '.data | length')
echo "✅ Found $TRACE_COUNT traces for $SERVICE_NAME"

# Check for expected operations
EXPECTED_OPERATIONS=("task.created" "task.completed" "step.processed")
for op in "${EXPECTED_OPERATIONS[@]}"; do
    if echo "$TRACES" | jq -r '.data[].spans[].operationName' | grep -q "$op"; then
        echo "✅ Found expected operation: $op"
    else
        echo "⚠️  Missing expected operation: $op"
    fi
done

echo "🎉 Jaeger validation completed!"
```

#### 2. Prometheus Metrics Validation

```bash
#!/bin/bash
# scripts/validate_prometheus_metrics.sh

PROMETHEUS_URL="http://localhost:9090"
TASKER_METRICS_URL="http://localhost:3000/tasker/metrics"

echo "📊 Validating Prometheus metrics for Tasker..."

# Check connectivity
curl -f "$PROMETHEUS_URL/-/healthy" > /dev/null 2>&1 || {
    echo "❌ Prometheus not accessible"
    exit 1
}

curl -f "$TASKER_METRICS_URL" > /dev/null 2>&1 || {
    echo "❌ Tasker metrics not accessible"
    exit 1
}

# Validate metrics endpoint
TASKER_METRICS=$(curl -s "$TASKER_METRICS_URL")
METRIC_COUNT=$(echo "$TASKER_METRICS" | grep -c "^[a-zA-Z]" || true)
echo "✅ Tasker exposing $METRIC_COUNT metrics"

# Check expected metrics
EXPECTED_METRICS=(
    "tasker_tasks_total"
    "tasker_steps_total"
    "tasker_workflow_duration_seconds"
    "tasker_active_connections"
)

for metric in "${EXPECTED_METRICS[@]}"; do
    if echo "$TASKER_METRICS" | grep -q "^$metric"; then
        echo "✅ Found metric: $metric"
    else
        echo "⚠️  Missing metric: $metric"
    fi
done

# Validate Prometheus ingestion
PROM_METRICS=$(curl -s "$PROMETHEUS_URL/api/v1/label/__name__/values" | jq -r '.data[] | select(contains("tasker"))')
PROM_METRIC_COUNT=$(echo "$PROM_METRICS" | wc -l)
echo "✅ Prometheus has $PROM_METRIC_COUNT Tasker metrics"

# Check scrape health
SCRAPE_HEALTH=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=up{job=\"tasker-metrics\"}" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
if [ "$SCRAPE_HEALTH" = "1" ]; then
    echo "✅ Tasker metrics scrape is healthy"
else
    echo "❌ Tasker metrics scrape is down"
fi

echo "🎉 Prometheus validation completed!"
```

#### 3. End-to-End Telemetry Validation

```bash
#!/bin/bash
# scripts/validate_e2e_telemetry.sh

echo "🚀 Running end-to-end telemetry validation..."

# Generate test workload
echo "📝 Generating test workload..."
curl -X POST http://localhost:3000/tasker/graphql \
  -H "Content-Type: application/json" \
  -d '{
    "query": "mutation { createTask(input: { namedTaskName: \"test_workflow\", context: \"{\\\"test\\\": true}\" }) { task { id } } }"
  }' > /dev/null

sleep 5  # Allow telemetry propagation

# Run validations
./scripts/validate_jaeger_traces.sh
./scripts/validate_prometheus_metrics.sh

# Cross-validate correlation
RECENT_TASKS=$(curl -s "http://localhost:16686/api/traces?service=tasker&lookback=5m" | jq '.data | length')
TASK_METRIC=$(curl -s "http://localhost:9090/api/v1/query?query=increase(tasker_tasks_total[5m])" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")

echo "📈 Recent task traces: $RECENT_TASKS"
echo "📊 Task metric increase: $TASK_METRIC"

if [ "$RECENT_TASKS" -gt 0 ] && [ "$(echo "$TASK_METRIC > 0" | bc)" -eq 1 ]; then
    echo "✅ Trace-metric correlation validated"
else
    echo "⚠️  Trace-metric correlation issue detected"
fi

echo "🎉 End-to-end telemetry validation completed!"
```

### Integration Testing Strategies

#### Non-Failing Test Integration

```ruby
# spec/integration/telemetry_export_spec.rb
RSpec.describe 'Telemetry Export Integration', type: :integration do
  it 'exports metrics to Prometheus format', :prometheus do
    # Generate test metrics
    backend = Tasker::Telemetry::MetricsBackend.instance
    backend.counter('test_counter').increment(5)
    backend.gauge('test_gauge').set(42)

    # Export and validate
    result = backend.export
    prometheus_exporter = Tasker::Telemetry::PrometheusExporter.new
    export_result = prometheus_exporter.safe_export(result)

    expect(export_result[:success]).to be true
    expect(export_result[:data]).to include('test_counter 5')
    expect(export_result[:data]).to include('test_gauge 42')

    # Optional: Send to real Prometheus if available
    send_to_prometheus(export_result[:data]) if ENV['PROMETHEUS_PUSHGATEWAY_URL']
  end

  private

  def send_to_prometheus(metrics_data)
    uri = URI("#{ENV['PROMETHEUS_PUSHGATEWAY_URL']}/metrics/job/tasker-test")
    Net::HTTP.post(uri, metrics_data, 'Content-Type' => 'text/plain')
  end
end
```

#### CI/CD Integration

```yaml
# .github/workflows/telemetry-validation.yml
name: Telemetry Validation

on:
  pull_request:
    paths:
      - 'lib/tasker/telemetry/**'

jobs:
  validate-telemetry:
    runs-on: ubuntu-latest

    services:
      jaeger:
        image: jaegertracing/all-in-one:1.47
        ports:
          - 16686:16686
        options: >-
          --health-cmd "curl -f http://localhost:16686/api/services"
          --health-interval 10s

      prometheus:
        image: prom/prometheus:v2.45.0
        ports:
          - 9090:9090

    steps:
      - uses: actions/checkout@v3
      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      - name: Run telemetry validation
        run: ./scripts/validate_e2e_telemetry.sh
```

This comprehensive validation approach ensures Tasker's telemetry works correctly with real-world observability infrastructure.

---

### 🔍 **Phase 4.3: Performance Profiling Integration**
**Timeline**: 4-5 days
**Impact**: Medium-High - Enables data-driven optimization

#### **Architecture Overview**
Integrate performance monitoring into existing orchestration components with automatic bottleneck detection.

#### **Implementation Components**

##### **4.3.1 Performance Monitoring Wrapper**
```ruby
# lib/tasker/performance/monitor.rb
module Tasker::Performance
  class Monitor
    include Singleton

    def initialize
      @config = Tasker.configuration.telemetry
      @store = Tasker::Metrics::Store.instance
    end

    # Monitor execution with automatic metrics collection
    def monitor(operation_name, context = {})
      return yield unless @config.performance_monitoring_enabled

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      start_memory = current_memory_usage

      result = yield

      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end_memory = current_memory_usage

      duration = end_time - start_time
      memory_delta = end_memory - start_memory

      record_performance_metrics(operation_name, duration, memory_delta, context)
      check_performance_thresholds(operation_name, duration, memory_delta, context)

      result
    end

    # Check for performance bottlenecks
    def check_performance_thresholds(operation, duration, memory_delta, context)
      if duration > @config.slow_query_threshold_seconds
        publish_slow_operation_event(operation, duration, context)
      end

      if memory_delta > (@config.memory_threshold_mb * 1_048_576) # Convert MB to bytes
        publish_memory_spike_event(operation, memory_delta, context)
      end
    end

    private

    def current_memory_usage
      # Ruby memory usage in bytes
      GC.stat[:heap_allocated_pages] * GC::INTERNAL_CONSTANTS[:HEAP_PAGE_SIZE]
    rescue
      0 # Fallback if GC stats unavailable
    end

    def record_performance_metrics(operation, duration, memory_delta, context)
      tags = { operation: operation }.merge(context.slice(:task_id, :step_id))

      @store.record_histogram('tasker_operation_duration_seconds', duration, tags)
      @store.record_histogram('tasker_memory_delta_bytes', memory_delta.abs, tags) if memory_delta != 0
    end

    def publish_slow_operation_event(operation, duration, context)
      Tasker::Events::Publisher.instance.publish(
        Tasker::Constants::ObservabilityEvents::Performance::SLOW_OPERATION,
        operation: operation,
        duration: duration,
        threshold: @config.slow_query_threshold_seconds,
        context: context,
        timestamp: Time.current
      )
    end

    def publish_memory_spike_event(operation, memory_delta, context)
      Tasker::Events::Publisher.instance.publish(
        Tasker::Constants::ObservabilityEvents::Performance::MEMORY_SPIKE,
        operation: operation,
        memory_delta_mb: (memory_delta / 1_048_576.0).round(2),
        threshold_mb: @config.memory_threshold_mb,
        context: context,
        timestamp: Time.current
      )
    end
  end
end
```

##### **4.3.2 SQL Query Monitoring Enhancement**
```ruby
# lib/tasker/performance/sql_monitor.rb
class Tasker::Performance::SqlMonitor
  def initialize
    @config = Tasker.configuration.telemetry
    @monitor = Tasker::Performance::Monitor.instance
    subscribe_to_sql_events if @config.performance_monitoring_enabled
  end

  private

  def subscribe_to_sql_events
    ActiveSupport::Notifications.subscribe('sql.active_record') do |name, start, finish, id, payload|
      next if skip_sql_monitoring?(payload)

      duration = finish - start

      # Record SQL performance metrics
      record_sql_metrics(duration, payload)

      # Check for slow queries
      if duration > @config.slow_query_threshold_seconds
        report_slow_query(duration, payload)
      end
    end
  end

  def skip_sql_monitoring?(payload)
    # Skip schema queries, very fast queries, etc.
    return true if payload[:sql]&.start_with?('SHOW', 'DESCRIBE', 'EXPLAIN')
    return true if payload[:name] == 'SCHEMA'

    false
  end

  def record_sql_metrics(duration, payload)
    tags = {
      table: extract_table_name(payload[:sql]),
      operation: extract_operation_type(payload[:sql])
    }

    Tasker::Metrics::Store.instance.record_histogram('tasker_sql_duration_seconds', duration, tags)
    Tasker::Metrics::Store.instance.increment_counter('tasker_sql_queries_total', 1, tags)
  end

  def report_slow_query(duration, payload)
    Tasker::Events::Publisher.instance.publish(
      Tasker::Constants::ObservabilityEvents::Performance::SLOW_SQL_QUERY,
      duration: duration,
      sql: payload[:sql]&.first(500), # Truncate for logging
      name: payload[:name],
      threshold: @config.slow_query_threshold_seconds,
      timestamp: Time.current
    )
  end

  def extract_table_name(sql)
    return 'unknown' unless sql

    # Simple table extraction - could be enhanced
    if sql.match(/FROM\s+(\w+)/i)
      $1
    elsif sql.match(/UPDATE\s+(\w+)/i)
      $1
    elsif sql.match(/INSERT\s+INTO\s+(\w+)/i)
      $1
    else
      'unknown'
    end
  end

  def extract_operation_type(sql)
    return 'unknown' unless sql

    case sql.strip.upcase
    when /^SELECT/ then 'select'
    when /^INSERT/ then 'insert'
    when /^UPDATE/ then 'update'
    when /^DELETE/ then 'delete'
    else 'other'
    end
  end
end
```

##### **4.3.3 Orchestration Performance Integration**
```ruby
# Enhanced lib/tasker/orchestration/workflow_coordinator.rb (additions)
module Tasker::Orchestration
  class WorkflowCoordinator
    # ... existing code ...

    private

    def execute_with_monitoring
      Tasker::Performance::Monitor.instance.monitor('workflow_coordination', task_id: @task.task_id) do
        yield
      end
    end

    def find_viable_steps_with_monitoring
      Tasker::Performance::Monitor.instance.monitor('find_viable_steps', task_id: @task.task_id) do
        # existing find_viable_steps logic
      end
    end
  end
end

# Enhanced lib/tasker/orchestration/step_executor.rb (additions)
module Tasker::Orchestration
  class StepExecutor
    # ... existing code ...

    private

    def execute_step_with_monitoring(step)
      Tasker::Performance::Monitor.instance.monitor(
        'step_execution',
        task_id: step.task.task_id,
        step_id: step.workflow_step_id,
        step_name: step.name
      ) do
        # existing step execution logic
        yield
      end
    end
  end
end
```

#### **Files to Create/Modify**
```
lib/tasker/performance/monitor.rb              # New - Core performance monitoring
lib/tasker/performance/sql_monitor.rb          # New - SQL query monitoring
lib/tasker/performance/bottleneck_detector.rb  # New - Bottleneck identification
lib/tasker/orchestration/workflow_coordinator.rb # Enhanced - Add monitoring
lib/tasker/orchestration/step_executor.rb      # Enhanced - Add monitoring
lib/tasker/constants/observability_events.rb   # Enhanced - Add performance events
spec/lib/tasker/performance/                   # New - Performance tests
```

## Enhanced Configuration Integration

### **Comprehensive Telemetry Configuration**
```ruby
# lib/tasker/types/telemetry_config.rb (Enhanced)
class TelemetryConfig < BaseConfig
  # Structured logging configuration
  attribute :structured_logging_enabled, Types::Bool.default(true)
  attribute :correlation_id_header, Types::String.default('X-Correlation-ID')
  attribute :log_level, Types::String.default('info')
  attribute :log_format, Types::String.default('json')

  # Metrics configuration
  attribute :metrics_enabled, Types::Bool.default(true)
  attribute :metrics_endpoint, Types::String.default('/tasker/metrics')
  attribute :metrics_format, Types::String.default('prometheus')
  attribute :metrics_auth_required, Types::Bool.default(false)

  # Performance monitoring configuration
  attribute :performance_monitoring_enabled, Types::Bool.default(true)
  attribute :slow_query_threshold_seconds, Types::Float.default(1.0)
  attribute :memory_threshold_mb, Types::Integer.default(100)
  attribute :bottleneck_analysis_enabled, Types::Bool.default(true)

  # Event filtering and sampling
  attribute :event_sampling_rate, Types::Float.default(1.0) # 100% by default
  attribute :filtered_events, Types::Array.of(Types::String).default([].freeze)

  # Memory and performance optimizations
  attribute :max_stored_samples, Types::Integer.default(1000)
  attribute :metrics_retention_hours, Types::Integer.default(24)
end
```

### **Engine Integration**
```ruby
# lib/tasker/engine.rb (Enhanced)
module Tasker
  class Engine < ::Rails::Engine
    # ... existing code ...

    initializer 'tasker.observability', after: 'tasker.configuration' do
      if Tasker.configuration.telemetry.structured_logging_enabled
        require 'tasker/concerns/structured_logging'
      end

      if Tasker.configuration.telemetry.metrics_enabled
        # Initialize metrics collection
        require 'tasker/metrics/store'
        require 'tasker/metrics/core_subscriber'

        # Start core metrics subscriber
        Tasker::Metrics::CoreSubscriber.subscribe(Tasker::Events::Publisher.instance)
      end

      if Tasker.configuration.telemetry.performance_monitoring_enabled
        require 'tasker/performance/monitor'
        require 'tasker/performance/sql_monitor'

        # Initialize performance monitoring
        Tasker::Performance::SqlMonitor.new
      end
    end
  end
end
```

## Streamlined Implementation Approach

### **Phase 1: Foundation Enhancement (Days 1-4)**
**Goal**: Implement structured logging and native metrics backend

1. **Day 1-2**: Structured Logging Implementation
   - Create `StructuredLogging` concern with correlation ID support
   - Enhance `EventPublisher` with structured logging
   - Add JSON formatter and parameter filtering

2. **Day 3-4**: Native Metrics Backend
   - Implement metrics storage (Store, Histogram, Counter, Gauge)
   - Create `CoreSubscriber` using existing BaseSubscriber infrastructure
   - Add metrics controller and routes

### **Phase 2: Performance Integration (Days 5-8)**
**Goal**: Add performance monitoring and bottleneck detection

1. **Day 5-6**: Performance Monitor Integration
   - Create performance monitoring wrapper
   - Integrate with orchestration components
   - Add SQL query monitoring

2. **Day 7-8**: Testing and Documentation
   - Comprehensive test coverage
   - Performance benchmarking
   - Documentation updates

### **Simplified File Structure**
```
lib/tasker/
├── concerns/
│   └── structured_logging.rb              # New - Correlation ID + JSON logging
├── metrics/
│   ├── store.rb                           # New - Thread-safe storage
│   ├── histogram.rb                       # New - Histogram implementation
│   ├── counter.rb                         # New - Counter implementation
│   ├── gauge.rb                           # New - Gauge implementation
│   └── core_subscriber.rb                 # New - Event-based collection
├── performance/
│   ├── monitor.rb                         # New - Performance wrapper
│   └── sql_monitor.rb                     # New - SQL monitoring
└── types/
    └── telemetry_config.rb                # Enhanced - Observability config

app/controllers/tasker/
└── metrics_controller.rb                  # New - Metrics endpoint

config/
└── routes.rb                              # Enhanced - Metrics routes
```

## Success Criteria & Validation

### **Phase 1 Success Metrics**
- ✅ Correlation IDs appear in all workflow logs
- ✅ JSON structured logging with consistent format
- ✅ Metrics collection from existing events
- ✅ Prometheus-compatible metrics endpoint

### **Phase 2 Success Metrics**
- ✅ Performance monitoring with <2% overhead
- ✅ Automatic slow query detection
- ✅ Memory spike identification
- ✅ Integration with existing orchestration

### **Production Readiness Validation**
- ✅ Thread-safe metrics collection
- ✅ Configurable feature flags
- ✅ Memory-efficient storage
- ✅ Zero breaking changes

## Risk Mitigation Strategy

### **Performance Impact**
- Feature flags for all observability features
- Configurable sampling rates for expensive operations
- Memory-bounded metric storage with automatic cleanup
- Performance benchmarks before and after implementation

### **Backward Compatibility**
- All new features are opt-in by default
- Existing event system completely unchanged
- Configuration with sensible production defaults
- No modifications to public APIs

### **Testing Strategy**
- Unit tests for all new components
- Integration tests for event-to-metrics pipeline
- Performance tests for overhead measurement
- Memory leak detection in long-running scenarios

This refined approach leverages Tasker's existing strong observability foundation while adding the critical missing pieces for production monitoring. The implementation is focused, practical, and builds incrementally on proven patterns already in the codebase.

## Immediate Next Steps

### **1. Begin Implementation (Day 1)**
Start with structured logging as it has the least complexity and highest immediate value:

```bash
# Create structured logging concern
touch lib/tasker/concerns/structured_logging.rb

# Create correlation ID generator
touch lib/tasker/logging/correlation_id_generator.rb

# Create JSON formatter
touch lib/tasker/logging/json_formatter.rb
```

### **2. Development Workflow**
```bash
# Work in observability-enhancements branch
git checkout observability-enhancements

# Create feature branch for each component
git checkout -b feature/structured-logging
git checkout -b feature/native-metrics
git checkout -b feature/performance-monitoring
```

### **3. Testing Approach**
```bash
# Run existing tests to ensure no regressions
bundle exec rspec

# Add new test files as components are created
touch spec/lib/tasker/concerns/structured_logging_spec.rb
touch spec/lib/tasker/metrics/store_spec.rb
touch spec/lib/tasker/performance/monitor_spec.rb
```

### **4. Configuration Integration**
```ruby
# First enhancement to telemetry_config.rb
# Add these attributes to existing TelemetryConfig class:
attribute :structured_logging_enabled, Types::Bool.default(true)
attribute :correlation_id_header, Types::String.default('X-Correlation-ID')
attribute :metrics_enabled, Types::Bool.default(true)
```

## Implementation Priority Queue

### **Immediate Priority (Week 1)**
1. **Structured Logging Concern** - Highest impact, lowest risk
2. **Native Metrics Store** - Builds on existing subscriber infrastructure
3. **Core Metrics Subscriber** - Leverages existing BaseSubscriber pattern
4. **Metrics Controller** - Simple REST endpoint for metrics export

### **Secondary Priority (Week 2)**
1. **Performance Monitor** - Adds valuable bottleneck detection
2. **SQL Monitor** - Critical for identifying database performance issues
3. **Integration Testing** - Ensure everything works together
4. **Documentation Updates** - Complete the observability picture

## Expected Outcomes

By implementing this observability enhancement plan, Tasker will achieve:

### **Production Monitoring Excellence**
- **Complete Traceability**: Every workflow execution tracked with correlation IDs
- **Performance Visibility**: Real-time metrics on task/step execution
- **Proactive Issue Detection**: Automatic identification of slow queries and memory spikes
- **External System Integration**: Prometheus/Grafana compatible metrics export

### **Developer Experience Enhancement**
- **Easier Debugging**: Structured logs with correlation IDs across distributed workflows
- **Performance Insights**: Clear visibility into workflow bottlenecks
- **Configuration Simplicity**: Sensible defaults with easy customization
- **Zero Breaking Changes**: All existing functionality preserved

### **Enterprise Readiness**
- **Scalable Monitoring**: Thread-safe metrics collection for high-volume workloads
- **Security Conscious**: Parameter filtering for sensitive data in logs/metrics
- **Memory Efficient**: Bounded storage with automatic cleanup
- **Feature Toggles**: Complete control over observability overhead

This implementation plan transforms Tasker from having excellent workflow orchestration to having world-class production observability, making it suitable for mission-critical enterprise deployments while maintaining its developer-friendly design principles.

## Migration Strategy

### **Phase 1: Foundation (Days 1-3)**
1. Implement structured logging concern
2. Add correlation ID generation
3. Enhance existing event publisher
4. Basic metrics collection infrastructure

### **Phase 2: Integration (Days 4-7)**
1. Integrate structured logging across orchestration components
2. Event-based metrics collection
3. Metrics endpoint implementation
4. Basic performance monitoring

### **Phase 3: Advanced Features (Days 8-12)**
1. Performance profiling system
2. Bottleneck detection
3. SQL query monitoring
4. Workflow performance analysis

### **Phase 4: Documentation & Testing (Days 13-15)**
1. Comprehensive test coverage
2. Documentation updates
3. Configuration examples
4. Performance benchmarking

## Success Metrics

### **Observability Completeness**
- ✅ Correlation ID tracking across all workflows
- ✅ Structured JSON logging with context
- ✅ Real-time metrics collection
- ✅ Performance bottleneck detection

### **Production Readiness**
- ✅ <5% performance overhead
- ✅ Memory-efficient metrics storage
- ✅ Configurable monitoring thresholds
- ✅ Integration with external monitoring systems

### **Developer Experience**
- ✅ Simple configuration API
- ✅ Clear performance insights
- ✅ Actionable bottleneck reports
- ✅ Zero breaking changes

## Dependencies & Considerations

### **Required Dependencies**
- No new external gems (pure Ruby implementation)
- Builds on existing event system
- Compatible with all Rails versions

### **Optional Integrations**
- Prometheus/Grafana compatibility
- OpenTelemetry integration
- External APM tool compatibility
- Log aggregation system integration

## Risk Mitigation

### **Performance Impact**
- Feature flags for disabling observability
- Configurable sampling rates
- Asynchronous processing options
- Memory-efficient data structures

### **Backward Compatibility**
- All new features are opt-in
- Existing event system unchanged
- Configuration with sensible defaults
- No breaking API changes

## Next Steps

1. **Review and Approve Plan**: Stakeholder review of implementation approach
2. **Setup Development Branch**: Create observability-enhancement branch
3. **Begin Phase 4.1**: Start with structured logging implementation
4. **Iterative Development**: Build and test each component incrementally
5. **Integration Testing**: End-to-end observability validation

This implementation plan provides a comprehensive observability enhancement that builds on Tasker's existing strengths while adding critical production monitoring capabilities.

---

## **🔍 COMPREHENSIVE TELEMETRY ARCHITECTURE ANALYSIS**

*Updated after Phase 4.1 completion and detailed TelemetrySubscriber review*

### **Current TelemetrySubscriber Architecture Assessment**

#### **✅ Strong Foundation Identified**
1. **Solid BaseSubscriber Architecture** - Proper error handling, event routing, OpenTelemetry integration
2. **Hierarchical Span Creation** - Task spans as parents with step spans as children
3. **Production-Ready Features** - Telemetry filtering, configuration validation, defensive coding
4. **Rich Attribute Extraction** - Comprehensive event data conversion for OpenTelemetry

#### **🚨 Critical Gaps Discovered**

**1. Limited Event Coverage (8 of 40+ available events)**
```ruby
# CURRENT: Only 8 events subscribed in TelemetrySubscriber
subscribe_to INITIALIZE_REQUESTED, START_REQUESTED, COMPLETED, FAILED,    # Task: 4 events
             EXECUTION_REQUESTED, COMPLETED, FAILED, RETRY_REQUESTED      # Step: 4 events

# MISSING: 35+ critical lifecycle events including:
# - WorkflowEvents::VIABLE_STEPS_DISCOVERED (orchestration visibility)
# - ObservabilityEvents::Step::BACKOFF (retry cycle monitoring)
# - ObservabilityEvents::Task::ENQUEUE (job queue observability)
# - ObservabilityEvents::Task::FINALIZE (task completion processing)
# - StepEvents::BEFORE_HANDLE (handler execution spans)
# - Database operation events (query performance spans)
# - Dependency resolution events (critical path analysis)
```

**2. Incomplete Span Hierarchy (2 levels vs needed 5+)**
```ruby
# CURRENT: Simple 2-level hierarchy
task_execution → step_execution

# NEEDED: Comprehensive 5+ level hierarchy
task_execution
├── workflow_orchestration
│   ├── step_batch_execution
│   │   ├── individual_steps
│   │   └── state_transitions
│   └── dependency_resolution
└── database_operations
```

**3. Zero Native Metrics Collection**
- All telemetry routed to OpenTelemetry spans only
- No aggregated metrics for operational dashboards
- Missing Prometheus `/tasker/metrics` endpoint functionality
- No thread-safe metrics storage backend

**4. Missing Event-Driven Intelligence**
- No intelligent routing between traces vs metrics
- Manual subscription management vs declarative event mapping
- Underutilization of robust 40+ event pub/sub system

---

## **🎯 PHASE 4.2: STRATEGIC EVOLUTION PLAN**

### **Core Strategy: Event-Driven Telemetry Router**

**Philosophy**: Preserve all existing TelemetrySubscriber functionality while dramatically expanding observability through intelligent event routing that leverages our robust event pub/sub system.

### **Phase 4.2.1: TelemetryEventRouter Foundation** (Days 1-2)

#### **Intelligent Event Routing Core**
```ruby
# The evolution preserves existing functionality while adding intelligence
class Tasker::Telemetry::EventRouter
  def self.configure
    # PRESERVE: All current 8 events → both traces AND metrics
    map 'task.initialize_requested' => [:trace, :metrics]
    map 'task.start_requested' => [:trace, :metrics]
    map 'task.completed' => [:trace, :metrics]
    map 'task.failed' => [:trace, :metrics]
    map 'step.execution_requested' => [:trace, :metrics]
    map 'step.completed' => [:trace, :metrics]
    map 'step.failed' => [:trace, :metrics]
    map 'step.retry_requested' => [:trace, :metrics]

    # ENHANCE: Add missing lifecycle events with intelligent routing
    map 'workflow.viable_steps_discovered' => [:trace, :metrics]
    map 'observability.step.backoff' => [:trace, :metrics]
    map 'observability.task.enqueue' => [:metrics]    # Job queue metrics only
    map 'observability.task.finalize' => [:trace]     # Detailed spans only
    map 'step.before_handle' => [:trace]              # Handler execution spans

    # EXTEND: Database and dependency events
    map 'database.query_executed' => [:trace, :metrics]
    map 'dependency.resolved' => [:trace]
    map 'batch.step_execution' => [:trace, :metrics]
  end
end
```

#### **Declarative Configuration Benefits**
- **Zero Breaking Changes** - All existing spans continue working
- **Intelligent Routing** - Events routed to appropriate backends (traces vs metrics)
- **Scalable Subscriptions** - Easy to add new events without code changes
- **Performance Optimization** - Route expensive traces vs cheap metrics appropriately

### **Phase 4.2.2: Native Metrics Backend** (Days 3-4)

#### **Thread-Safe Metrics Collection**
```ruby
class Tasker::Metrics::Backend
  # Thread-safe metric collection with multiple output formats
  def record_counter(name, value, tags = {})
  def record_histogram(name, value, tags = {})
  def record_gauge(name, value, tags = {})

  # Export capabilities
  def export_prometheus    # /tasker/metrics endpoint
  def export_json          # Alternative format
  def health_check         # Backend status
end
```

#### **Production-Ready Features**
- **Thread-Safe Storage** - Concurrent metric collection without locks
- **Memory Management** - Configurable retention with automatic cleanup
- **Multiple Formats** - Prometheus, JSON, and custom export formats
- **Performance Optimized** - O(1) metric recording with efficient aggregation

### **Phase 4.2.2.3: Plugin Architecture for Custom Exporters**

#### **Framework-Appropriate Export Pipeline**
```ruby
class ExportPipeline
  def initialize
    @exporters = {}
    register_default_exporters
  end

  def register_exporter(name, exporter_class)
    @exporters[name] = exporter_class
  end

  def export(format: :prometheus, include_instances: false)
    exporter = @exporters[format]
    raise ArgumentError, "Unknown format: #{format}" unless exporter

    metrics_data = gather_metrics_data(include_instances)
    exporter.new.export(metrics_data)
  end

  private

  def register_default_exporters
    # ✅ Framework provides industry-standard formats
    register_exporter(:prometheus, PrometheusExporter)  # Already implemented
    register_exporter(:json, JSONExporter)              # Standard JSON format
    register_exporter(:csv, CSVExporter)                # Data analysis format

    # ✅ Plugin architecture for developer extensibility
    # Developers can register custom exporters via configuration
  end
end
```

#### **Developer-Facing Plugin System**
```ruby
# config/initializers/tasker_metrics.rb
Tasker::Telemetry::MetricsBackend.configure do |config|
  # Cache-agnostic configuration
  config.retention_window = 5.minutes
  config.export_safety_margin = 1.minute
  config.sync_interval = 30.seconds

  # Multi-container coordination (auto-detected)
  config.cross_container_coordination = :auto
  config.atomic_operations = :auto
  config.distributed_export = :auto

  # Export targets with different strategies
  config.export_targets = {
    prometheus_file: {
      strategy: :scheduled,
      interval: 1.minute,
      path: '/tmp/metrics.prom'
    },
    http_push: {
      strategy: :threshold,
      threshold: 1000,
      endpoint: 'https://metrics.example.com/push'
    }
  }

  # ✅ Developer extensibility - register custom exporters
  config.register_exporter(:datadog, DataDogExporter)      # Developer-provided
  config.register_exporter(:influxdb, InfluxDBExporter)    # Developer-provided
end

# ✅ Developer provides vendor integrations via event subscribers
class MetricsSubscriber < BaseSubscriber
  subscribe_to 'task.completed', 'task.failed'

  def handle_task_completed(event)
    # Developer chooses their metrics system
    StatsD.histogram('task.duration', event[:duration])
    # OR use native metrics backend
    backend.counter('tasks_completed', **extract_labels(event)).increment
  end
end
```

---

## Real-World Telemetry Validation

### Overview

This section provides comprehensive validation approaches for ensuring Tasker's telemetry and metrics exports are correctly landing in production observability systems. We'll cover testing against local Docker setups for Jaeger and Prometheus, along with curl-based verification scripts.

### Local Development Environment Setup

#### Docker Compose for Observability Stack

```yaml
# docker-compose.observability.yml
version: '3.8'

services:
  jaeger:
    image: jaegertracing/all-in-one:1.47
    ports:
      - "16686:16686"    # Jaeger UI
      - "14250:14250"    # gRPC
      - "14268:14268"    # HTTP
      - "6831:6831/udp"  # UDP
      - "6832:6832/udp"  # UDP
    environment:
      - COLLECTOR_OTLP_ENABLED=true
      - COLLECTOR_ZIPKIN_HOST_PORT=:9411
    networks:
      - observability

  prometheus:
    image: prom/prometheus:v2.45.0
    ports:
      - "9090:9090"
    volumes:
      - ./config/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=200h'
      - '--web.enable-lifecycle'
    networks:
      - observability

  grafana:
    image: grafana/grafana:10.0.0
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana_data:/var/lib/grafana
      - ./config/grafana/provisioning:/etc/grafana/provisioning
    networks:
      - observability

  # OTEL Collector for advanced scenarios
  otel-collector:
    image: otel/opentelemetry-collector-contrib:0.81.0
    command: ["--config=/etc/otel-collector-config.yml"]
    volumes:
      - ./config/otel-collector-config.yml:/etc/otel-collector-config.yml
    ports:
      - "4317:4317"   # OTLP gRPC receiver
      - "4318:4318"   # OTLP HTTP receiver
      - "8888:8888"   # Prometheus metrics
    depends_on:
      - jaeger
      - prometheus
    networks:
      - observability

volumes:
  prometheus_data:
  grafana_data:

networks:
  observability:
    driver: bridge
```

#### Prometheus Configuration

```yaml
# config/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'tasker-metrics'
    static_configs:
      - targets: ['host.docker.internal:3000']  # Rails app
    metrics_path: '/tasker/metrics'
    scrape_interval: 30s
    scrape_timeout: 10s

  - job_name: 'otel-collector'
    static_configs:
      - targets: ['otel-collector:8888']
```

#### OpenTelemetry Collector Configuration

```yaml
# config/otel-collector-config.yml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 1s
    send_batch_size: 1024
    send_batch_max_size: 2048

exporters:
  jaeger:
    endpoint: jaeger:14250
    tls:
      insecure: true

  prometheus:
    endpoint: "0.0.0.0:8888"
    namespace: tasker
    const_labels:
      service: tasker-otel

  logging:
    loglevel: debug

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [jaeger, logging]

    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [prometheus, logging]
```

### Validation Scripts

#### 1. Jaeger Trace Validation

```bash
#!/bin/bash
# scripts/validate_jaeger_traces.sh

set -e

JAEGER_URL="http://localhost:16686"
SERVICE_NAME="tasker"
LOOKBACK="1h"

echo "🔍 Validating Jaeger traces for Tasker..."

# Check Jaeger health
echo "📡 Checking Jaeger connectivity..."
curl -f "$JAEGER_URL/api/services" > /dev/null 2>&1 || {
    echo "❌ Jaeger not accessible at $JAEGER_URL"
    exit 1
}

# Get services
echo "🔍 Fetching available services..."
SERVICES=$(curl -s "$JAEGER_URL/api/services" | jq -r '.data[]')

if echo "$SERVICES" | grep -q "$SERVICE_NAME"; then
    echo "✅ Tasker service found in Jaeger"
else
    echo "⚠️  Tasker service not found. Available services:"
    echo "$SERVICES"
    exit 1
fi

# Get traces for the last hour
echo "📊 Fetching recent traces..."
TRACES=$(curl -s "$JAEGER_URL/api/traces?service=$SERVICE_NAME&lookback=$LOOKBACK" | jq '.data[]')

if [ -z "$TRACES" ]; then
    echo "⚠️  No traces found for $SERVICE_NAME in the last $LOOKBACK"
    exit 1
fi

TRACE_COUNT=$(echo "$TRACES" | jq -s length)
echo "✅ Found $TRACE_COUNT traces for $SERVICE_NAME"

# Analyze trace operations
echo "🔍 Analyzing trace operations..."
OPERATIONS=$(echo "$TRACES" | jq -r '.spans[].operationName' | sort | uniq -c | sort -nr)

echo "📈 Top operations by span count:"
echo "$OPERATIONS" | head -10

# Check for specific Tasker operations
EXPECTED_OPERATIONS=("task.created" "task.completed" "step.processed" "workflow.executed")
for op in "${EXPECTED_OPERATIONS[@]}"; do
    if echo "$OPERATIONS" | grep -q "$op"; then
        echo "✅ Found expected operation: $op"
    else
        echo "⚠️  Missing expected operation: $op"
    fi
done

# Check trace duration distribution
echo "📊 Trace duration analysis..."
DURATIONS=$(echo "$TRACES" | jq -r '.spans[] | select(.operationName | contains("task")) | .duration')
if [ -n "$DURATIONS" ]; then
    AVG_DURATION=$(echo "$DURATIONS" | awk '{sum+=$1; count++} END {print sum/count/1000}')
    echo "⏱️  Average task duration: ${AVG_DURATION}ms"
fi

echo "🎉 Jaeger validation completed successfully!"
```

#### 2. Prometheus Metrics Validation

```bash
#!/bin/bash
# scripts/validate_prometheus_metrics.sh

set -e

PROMETHEUS_URL="http://localhost:9090"
TASKER_METRICS_URL="http://localhost:3000/tasker/metrics"

echo "📊 Validating Prometheus metrics for Tasker..."

# Check Prometheus health
echo "📡 Checking Prometheus connectivity..."
curl -f "$PROMETHEUS_URL/-/healthy" > /dev/null 2>&1 || {
    echo "❌ Prometheus not accessible at $PROMETHEUS_URL"
    exit 1
}

# Check Tasker metrics endpoint
echo "🔍 Checking Tasker metrics endpoint..."
curl -f "$TASKER_METRICS_URL" > /dev/null 2>&1 || {
    echo "❌ Tasker metrics not accessible at $TASKER_METRICS_URL"
    exit 1
}

# Get current metrics from Tasker
echo "📈 Fetching current Tasker metrics..."
TASKER_METRICS=$(curl -s "$TASKER_METRICS_URL")
METRIC_COUNT=$(echo "$TASKER_METRICS" | grep -c "^[a-zA-Z]" || true)

echo "✅ Tasker exposing $METRIC_COUNT metrics"

# Validate specific metrics exist
EXPECTED_METRICS=(
    "tasker_tasks_total"
    "tasker_steps_total"
    "tasker_workflow_duration_seconds"
    "tasker_active_connections"
    "tasker_cache_operations_total"
)

echo "🔍 Validating expected metrics..."
for metric in "${EXPECTED_METRICS[@]}"; do
    if echo "$TASKER_METRICS" | grep -q "^$metric"; then
        echo "✅ Found metric: $metric"
    else
        echo "⚠️  Missing metric: $metric"
    fi
done

# Query Prometheus for Tasker metrics
echo "🔍 Querying Prometheus for Tasker metrics..."
PROM_METRICS=$(curl -s "$PROMETHEUS_URL/api/v1/label/__name__/values" | jq -r '.data[] | select(contains("tasker"))')

if [ -z "$PROM_METRICS" ]; then
    echo "⚠️  No Tasker metrics found in Prometheus"
    echo "🔧 Check if Prometheus is scraping the /tasker/metrics endpoint"
    exit 1
fi

PROM_METRIC_COUNT=$(echo "$PROM_METRICS" | wc -l)
echo "✅ Prometheus has $PROM_METRIC_COUNT Tasker metrics"

# Validate metric values
echo "📊 Validating metric values..."
for metric in "${EXPECTED_METRICS[@]}"; do
    if echo "$PROM_METRICS" | grep -q "$metric"; then
        # Get latest value
        QUERY_RESULT=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=$metric" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "null")
        if [ "$QUERY_RESULT" != "null" ]; then
            echo "✅ $metric = $QUERY_RESULT"
        else
            echo "⚠️  $metric has no current value"
        fi
    fi
done

# Check scrape health
echo "🔍 Checking scrape health..."
SCRAPE_HEALTH=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=up{job=\"tasker-metrics\"}" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")

if [ "$SCRAPE_HEALTH" = "1" ]; then
    echo "✅ Tasker metrics scrape is healthy"
else
    echo "❌ Tasker metrics scrape is down"
    exit 1
fi

echo "🎉 Prometheus validation completed successfully!"
```

#### 3. End-to-End Telemetry Validation

```bash
#!/bin/bash
# scripts/validate_e2e_telemetry.sh

set -e

echo "🚀 Running end-to-end telemetry validation..."

# Generate test workload
echo "📝 Generating test workload..."
curl -X POST http://localhost:3000/tasker/graphql \
  -H "Content-Type: application/json" \
  -d '{
    "query": "mutation { createTask(input: { namedTaskName: \"test_workflow\", context: \"{\\\"test\\\": true}\" }) { task { id status } } }"
  }' > /dev/null

sleep 5  # Allow time for telemetry to propagate

# Validate traces
echo "🔍 Validating traces..."
./scripts/validate_jaeger_traces.sh

# Validate metrics
echo "📊 Validating metrics..."
./scripts/validate_prometheus_metrics.sh

# Cross-validate correlation
echo "🔗 Cross-validating trace-metric correlation..."
RECENT_TASKS=$(curl -s "http://localhost:16686/api/traces?service=tasker&operation=task.created&lookback=5m" | jq '.data | length')
TASK_METRIC=$(curl -s "http://localhost:9090/api/v1/query?query=increase(tasker_tasks_total[5m])" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")

echo "📈 Recent task traces: $RECENT_TASKS"
echo "📊 Task metric increase: $TASK_METRIC"

if [ "$RECENT_TASKS" -gt 0 ] && [ "$(echo "$TASK_METRIC > 0" | bc)" -eq 1 ]; then
    echo "✅ Trace-metric correlation validated"
else
    echo "⚠️  Trace-metric correlation issue detected"
fi

echo "🎉 End-to-end telemetry validation completed!"
```

#### 4. Performance Telemetry Validation

```bash
#!/bin/bash
# scripts/validate_performance_telemetry.sh

set -e

echo "⚡ Validating performance telemetry..."

# Generate load
echo "🔄 Generating performance test load..."
for i in {1..10}; do
    curl -X POST http://localhost:3000/tasker/graphql \
      -H "Content-Type: application/json" \
      -d '{
        "query": "mutation { createTask(input: { namedTaskName: \"performance_test\", context: \"{\\\"iteration\\\": '$i'}\" }) { task { id } } }"
      }' > /dev/null &
done

wait  # Wait for all requests to complete
sleep 10  # Allow telemetry to propagate

# Validate performance metrics
echo "📊 Validating performance metrics..."

# Check request duration percentiles
DURATION_P95=$(curl -s "http://localhost:9090/api/v1/query?query=histogram_quantile(0.95, tasker_workflow_duration_seconds_bucket)" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "null")

# Check throughput
THROUGHPUT=$(curl -s "http://localhost:9090/api/v1/query?query=rate(tasker_tasks_total[1m])" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "null")

# Check error rate
ERROR_RATE=$(curl -s "http://localhost:9090/api/v1/query?query=rate(tasker_tasks_total{status=\"error\"}[1m])" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")

echo "📈 Performance Metrics:"
echo "  ⏱️  95th percentile duration: ${DURATION_P95}s"
echo "  🚀 Throughput: ${THROUGHPUT} tasks/sec"
echo "  ❌ Error rate: ${ERROR_RATE} errors/sec"

# Validate trace performance data
SLOW_TRACES=$(curl -s "http://localhost:16686/api/traces?service=tasker&minDuration=1s&lookback=5m" | jq '.data | length')
echo "  🐌 Slow traces (>1s): $SLOW_TRACES"

if [ "$SLOW_TRACES" -gt 5 ]; then
    echo "⚠️  High number of slow traces detected"
else
    echo "✅ Performance telemetry looks healthy"
fi

echo "🎉 Performance telemetry validation completed!"
```

### Integration Testing in CI/CD

```yaml
# .github/workflows/telemetry-validation.yml
name: Telemetry Validation

on:
  pull_request:
    paths:
      - 'lib/tasker/telemetry/**'
      - 'spec/lib/tasker/telemetry/**'

jobs:
  validate-telemetry:
    runs-on: ubuntu-latest

    services:
      jaeger:
        image: jaegertracing/all-in-one:1.47
        ports:
          - 16686:16686
          - 14250:14250
        options: >-
          --health-cmd "curl -f http://localhost:16686/api/services"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

      prometheus:
        image: prom/prometheus:v2.45.0
        ports:
          - 9090:9090
        volumes:
          - ${{ github.workspace }}/config/prometheus.yml:/etc/prometheus/prometheus.yml

    steps:
      - uses: actions/checkout@v3

      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true

      - name: Setup test database
        run: |
          bundle exec rails db:create
          bundle exec rails db:migrate

      - name: Start Rails server
        run: |
          bundle exec rails server -p 3000 &
          sleep 10

      - name: Run telemetry validation
        run: |
          chmod +x scripts/validate_*.sh
          ./scripts/validate_e2e_telemetry.sh

      - name: Upload telemetry artifacts
        if: failure()
        uses: actions/upload-artifact@v3
        with:
          name: telemetry-logs
          path: |
            log/test.log
            tmp/telemetry_validation.log
```

### Testing Strategies

#### 1. Non-Failing Test Integration

```ruby
# spec/integration/telemetry_export_spec.rb
RSpec.describe 'Telemetry Export Integration', type: :integration do
  before(:all) do
    # Start background metrics export
    @export_thread = Thread.new do
      loop do
        Tasker::Telemetry::MetricsBackend.instance.sync_to_cache!
        sleep 30
      end
    end
  end

  after(:all) do
    @export_thread&.kill
  end

  it 'exports metrics to Prometheus format', :prometheus do
    # Generate test metrics
    backend = Tasker::Telemetry::MetricsBackend.instance
    backend.counter('test_counter').increment(5)
    backend.gauge('test_gauge').set(42)

    # Export metrics
    result = backend.export

    # Validate Prometheus format
    prometheus_exporter = Tasker::Telemetry::PrometheusExporter.new
    export_result = prometheus_exporter.safe_export(result)

    expect(export_result[:success]).to be true
    expect(export_result[:data]).to include('test_counter 5')
    expect(export_result[:data]).to include('test_gauge 42')

    # Optional: Send to real Prometheus if available
    if ENV['PROMETHEUS_PUSHGATEWAY_URL']
      send_to_prometheus(export_result[:data])
    end
  end

  private

  def send_to_prometheus(metrics_data)
    uri = URI("#{ENV['PROMETHEUS_PUSHGATEWAY_URL']}/metrics/job/tasker-test")
    Net::HTTP.post(uri, metrics_data, 'Content-Type' => 'text/plain')
  end
end
```

#### 2. Docker Compose Test Environment

```yaml
# docker-compose.test.yml
version: '3.8'

services:
  app:
    build: .
    environment:
      - RAILS_ENV=test
      - DATABASE_URL=postgresql://postgres:password@db:5432/tasker_test
      - JAEGER_ENDPOINT=http://jaeger:14268/api/traces
      - PROMETHEUS_PUSHGATEWAY_URL=http://prometheus:9091
    depends_on:
      - db
      - jaeger
      - prometheus
    volumes:
      - .:/app
    networks:
      - test-network

  db:
    image: postgres:15
    environment:
      - POSTGRES_PASSWORD=password
      - POSTGRES_DB=tasker_test
    networks:
      - test-network

  jaeger:
    image: jaegertracing/all-in-one:1.47
    environment:
      - COLLECTOR_OTLP_ENABLED=true
    networks:
      - test-network

  prometheus:
    image: prom/prometheus:v2.45.0
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--web.enable-lifecycle'
      - '--storage.tsdb.retention.time=1h'
    volumes:
      - ./config/prometheus.test.yml:/etc/prometheus/prometheus.yml
    networks:
      - test-network

networks:
  test-network:
    driver: bridge
```

This comprehensive validation approach ensures that Tasker's telemetry system works correctly with real-world observability infrastructure, providing confidence in production deployments.

---

## Next Steps

With Phase 4.2.2.3.1 complete, the next phases will focus on:

- **Phase 4.2.2.3.2**: Adaptive Sync Implementation (TTL-aware scheduling)
- **Phase 4.2.2.3.3**: Export Job Coordination (distributed locking)
- **Phase 4.2.2.3.4**: Production Testing & Validation

The plugin architecture foundation is now ready for extending Tasker's metrics capabilities while maintaining clean framework boundaries.
