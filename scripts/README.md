# Tasker 2.5.0 Scripts & Tools

This directory contains comprehensive validation scripts and application generators that prove Tasker's production readiness and provide enterprise-grade development tools.

## **🎯 COMPLETION STATUS: PRODUCTION READY** ✅

**Major Milestone Achieved**: All core components are now production-ready with enterprise-grade quality:

- ✅ **Application Generator**: Complete with Redis, Sidekiq, OpenTelemetry integration
- ✅ **ERB Templates**: All syntax issues resolved, modern patterns implemented
- ✅ **Configuration Validation**: All Dry::Struct type safety issues fixed
- ✅ **Infrastructure Integration**: Full stack deployment ready
- ✅ **Observability Validation**: Jaeger and Prometheus integration proven
- ✅ **Database Objects**: Automatic views and functions deployment

## **Strategic Mission**
1. **Validate** Tasker's enterprise-grade capabilities through comprehensive integration testing
2. **Generate** production-ready applications with enterprise templates and best practices
3. **Demonstrate** real-world workflows with complete observability stack validation

## Available Scripts & Tools

### **🚀 Application Template Generator** 🆕 **PRODUCTION READY**
**Files**: `create_tasker_app.rb` + `install-tasker-app.sh`

**MAJOR UPDATE**: Comprehensive production-ready application generator with enterprise-grade templates and infrastructure integration.

**Recent Breakthrough Improvements**:
- ✅ **ERB Template Engine**: Fixed all ERB syntax issues (removed problematic `-%>` endings)
- ✅ **Infrastructure Integration**: Automatic Redis + Sidekiq setup for production-ready job processing
- ✅ **OpenTelemetry Stack**: Complete observability gems when `--observability` flag enabled
- ✅ **Configuration Type Safety**: Fixed all Dry::Struct validation issues with proper types
- ✅ **Modern Step Handler Patterns**: Updated generator templates to use `process`/`process_results` methods
- ✅ **Production Database Objects**: Automatic copying of database views and functions

**Core Features**:
- **One-Line Creation**: `curl | bash` installer for instant setup
- **Enterprise Templates**: E-commerce, inventory, customer management workflows
- **Production Architecture**: Proper YAML configs, structured logging, observability
- **Real-World Patterns**: DummyJSON API integration, step handlers, ConfiguredTask pattern
- **Complete Stack**: Rails generators, comprehensive documentation, test suites
- **Infrastructure Ready**: Redis caching, Sidekiq background jobs, PostgreSQL setup
- **Observability Complete**: OpenTelemetry tracing, Prometheus metrics, structured logging

**Infrastructure Components**:
- **Redis**: Automatically uncommented and configured for caching
- **Sidekiq**: Added for background job processing with OpenTelemetry instrumentation
- **PostgreSQL**: Database setup with all 21 Tasker migrations
- **OpenTelemetry**: Complete instrumentation stack (Rails, ActiveRecord, HTTP, Redis, Sidekiq)
- **Prometheus**: Metrics collection and export configuration
- **Database Objects**: Automatic copying of SQL views and functions

**Template Quality**:
- **ERB Syntax**: All templates validated and working correctly
- **Type Safety**: Configuration values match Dry::Struct type requirements
- **Modern Patterns**: Uses current `process` methods instead of deprecated `handle`/`call`
- **Performance Configuration**: Comprehensive execution tuning examples for all environments
- **Production Ready**: Proper error handling, logging, and infrastructure integration

**Quick Start**:
```bash
# Interactive creation with full observability stack
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/scripts/install-tasker-app.sh | bash

# Custom application with specific templates
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/scripts/install-tasker-app.sh | bash -s -- \
  --app-name my-ecommerce-app \
  --tasks ecommerce \
  --non-interactive

# Minimal setup without observability
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/scripts/install-tasker-app.sh | bash -s -- \
  --app-name minimal-tasker \
  --no-observability \
  --non-interactive
```

**Generated Application Includes**:
- Complete Rails application with PostgreSQL
- Tasker gem installed via Git source (v2.5.0)
- All 21 Tasker migrations executed
- Database views and functions copied
- Redis and Sidekiq configured and ready
- 3 complete workflow examples (ecommerce, inventory, customer)
- OpenTelemetry instrumentation (when enabled)
- **Execution configuration examples** for performance tuning
- Comprehensive documentation and test suites

**Next Steps After Generation**:
```bash
cd your-app-name
bundle exec redis-server &          # Start Redis
bundle exec sidekiq &               # Start Sidekiq
bundle exec rails server            # Start Rails

# Visit your new Tasker application:
# http://localhost:3000/tasker/graphql     - GraphQL API
# http://localhost:3000/tasker/api-docs    - REST API docs
# http://localhost:3000/tasker/metrics     - Prometheus metrics
```

**Configuration Templates**:
The demo application builder now includes comprehensive execution configuration examples:

- **`tasker_configuration.rb.erb`**: Main configuration with execution settings
- **`execution_tuning_examples.rb.erb`**: Environment-specific tuning examples
  - Development: Conservative settings for local development
  - Production: High-performance settings for enterprise deployment
  - High-Performance: Maximum throughput for large-scale systems
  - API-Heavy: Optimized for external API workflows
  - Database-Intensive: Tuned for heavy database operations
  - Mixed Workload: Balanced settings for varied workflows
  - Testing: Minimal concurrency for test reliability

**Performance Tuning**: Each template includes detailed comments explaining when and how to adjust settings based on your system characteristics and workload patterns.

**Documentation**: See `docs/APPLICATION_GENERATOR.md` and `docs/EXECUTION_CONFIGURATION.md` for complete details.

### **🔍 Jaeger Integration Validator** ✅ COMPLETED
**File**: `validate_jaeger_integration.rb`

Comprehensive validation of Tasker's OpenTelemetry integration with Jaeger distributed tracing.

**Features**:
- **5 Validation Categories**: Connection, Workflow Execution, Trace Collection, Span Hierarchy, Trace Correlation
- **Advanced Span Analysis**: Parent-child relationships with detailed hierarchy mapping
- **Real Workflow Testing**: Linear, diamond, and parallel workflow patterns
- **Comprehensive Diagnostics**: OpenTelemetry configuration analysis and trace flushing tests
- **Production-Ready Error Handling**: StandardError exception handling with actionable recommendations

**Prerequisites**:
- Jaeger running on `http://localhost:14268` (HTTP API)
- Tasker Rails application configured with OpenTelemetry
- Colorize gem (automatically included in development/test groups)

**Usage**:
```bash
./scripts/validate_jaeger_integration.rb
```

**Sample Results** (Actual output from successful run):
```
🎯 Tasker 2.5.0 - Jaeger Integration Validator
✅ Jaeger Connection: PASS - Successfully connected to Jaeger
✅ Workflow Execution: PASS - Created and executed 3 workflows
✅ Trace Collection: PASS - Successfully collected 13 spans
✅ Span Hierarchy: PASS - Validated 10 parent-child relationships
✅ Trace Correlation: PASS - All spans properly correlated

📊 Span Analysis Results:
Linear Workflow: 4 spans, 3 parent-child relationships
Diamond Workflow: 5 spans, 4 parent-child relationships
Parallel Workflow: 4 spans, 3 parent-child relationships

⚡ Performance: Average 810ms span duration
```

### **📊 Prometheus Integration Validator** ✅ COMPLETED
**File**: `validate_prometheus_integration.rb`

Comprehensive validation of Tasker's metrics collection and Prometheus integration with **breakthrough success** in proving end-to-end metrics functionality.

**Features**:
- **6 Validation Categories**: Prometheus Connection, Metrics Endpoint, Workflow Execution, Metrics Collection, Query Validation, Performance Analysis
- **Advanced Metrics Analysis**: Automatic parsing and categorization (Counter, Gauge, Histogram)
- **Real Workflow Testing**: Execute 3 workflow patterns to generate authentic metrics
- **PromQL Query Validation**: Test standard Prometheus queries for dashboard compatibility
- **MetricsSubscriber Integration**: Automatic event-to-metrics bridging via EventRouter system
- **Production-Ready Architecture**: Full end-to-end validation of enterprise observability stack

**Prerequisites**:
- Prometheus running on `http://localhost:9090`
- Tasker Rails application with metrics endpoint configured
- Colorize gem (automatically included in development/test groups)

**Usage**:
```bash
./scripts/validate_prometheus_integration.rb
```

**Sample Results** (Actual output from successful run):
```
🎯 Tasker 2.5.0 - Prometheus Integration Validator
✅ MetricsSubscriber registered successfully
✅ Prometheus Connection: PASS - Successfully connected to Prometheus
✅ Metrics Endpoint: PASS - Tasker metrics endpoint accessible
✅ Workflow Execution: PASS - Created and executed 3 workflows
✅ Metrics Collection: PASS - Successfully collected 3 total metrics
✅ Query Validation: PASS - All 4 PromQL queries successful

📊 Metrics Analysis Results:
Counter metrics: 2 (step_completed_total: 22, task_completed_total: 3)
Histogram metrics: 1 (step_duration_seconds)
Total workflow activity: 22 steps completed across 3 tasks

⚡ Performance: 4 successful PromQL queries, full TSDB integration verified
```

**Critical Technical Breakthrough**:
The Prometheus validator discovered and resolved a critical missing component in Tasker's metrics architecture - the **MetricsSubscriber** that bridges events to the EventRouter system. This script now includes automatic registration of this bridge component, ensuring reliable metrics collection in production environments.

## **Architecture Insights**

### **Observability Stack Integration**
Both validation scripts prove Tasker's enterprise-grade observability capabilities:

- **Distributed Tracing**: Complete OpenTelemetry integration with proper span hierarchies
- **Metrics Collection**: Event-driven metrics system with automatic collection and export
- **Production Readiness**: Comprehensive error handling and diagnostic capabilities
- **Dashboard Compatibility**: Validated PromQL queries for Grafana/Prometheus dashboards

### **Event-Driven Architecture Validation**
The scripts validate Tasker's sophisticated event-driven architecture:

1. **Event Publishing**: `Events::Publisher` publishes lifecycle events
2. **Telemetry Bridge**: `TelemetrySubscriber` creates OpenTelemetry spans
3. **Metrics Bridge**: `MetricsSubscriber` routes events to EventRouter
4. **Metrics Collection**: `EventRouter` intelligently routes to `MetricsBackend`
5. **Export Systems**: `PrometheusExporter` formats metrics for consumption

## **Development Notes**

### **Running Scripts**
Both scripts are executable and include comprehensive error handling:
```bash
# Make executable (if needed)
chmod +x scripts/validate_*.rb

# Run individual validators
./scripts/validate_jaeger_integration.rb
./scripts/validate_prometheus_integration.rb
```

### **Troubleshooting**
- **Environment Loading**: Scripts automatically detect and load the appropriate Rails environment
- **Dependency Management**: All required gems are included in development/test groups
- **Service Requirements**: Ensure Jaeger (port 14268) and Prometheus (port 9090) are running
- **Metrics Issues**: The Prometheus validator includes automatic MetricsSubscriber registration

## **Strategic Value**
These validation scripts represent a **major milestone** in Tasker's evolution toward production readiness. They provide:

- **Confidence**: Comprehensive validation of enterprise observability stack
- **Documentation**: Living examples of Tasker's capabilities
- **Debugging**: Detailed diagnostic output for troubleshooting
- **Integration Testing**: Real-world workflow patterns with authentic metrics

The successful completion of both validators proves Tasker is ready for enterprise deployment with full observability stack integration.
