# Tasker 2.5.0 Integration Validation Scripts

This directory contains comprehensive integration validation scripts that prove Tasker's production readiness through real-world observability stack integration testing.

## Overview

The integration validation scripts demonstrate Tasker's enterprise-grade capabilities by:

- **Executing real workflow patterns** with distributed tracing
- **Querying observability APIs** to validate data collection
- **Analyzing trace/metric structure** to ensure proper integration
- **Generating comprehensive reports** with actionable insights
- **Providing production readiness assessment** with clear pass/fail criteria

## Scripts

### 🔍 `validate_jaeger_integration.rb`

Validates Tasker's integration with Jaeger distributed tracing by executing sample workflows and analyzing trace collection.

**Features:**
- **Connection Testing**: Validates Jaeger HTTP API connectivity and service discovery
- **Workflow Execution**: Tests linear, diamond, and parallel workflow patterns with child spans
- **Trace Analysis**: Validates span hierarchy and parent-child relationships with detailed debugging
- **Performance Metrics**: Analyzes span duration, timing, and trace correlation
- **Comprehensive Reporting**: Detailed pass/fail status with actionable recommendations
- **Enhanced Diagnostics**: OpenTelemetry configuration analysis and trace flush status
- **Improved Error Handling**: Robust error handling with detailed error messages

**Usage:**
```bash
# Use default Jaeger URL (http://localhost:16686)
bundle exec rails runner scripts/validate_jaeger_integration.rb

# Use custom Jaeger URL
bundle exec rails runner scripts/validate_jaeger_integration.rb http://jaeger.example.com:16686
```

**Prerequisites:**
- Jaeger running and accessible at specified URL
- OpenTelemetry SDK properly configured in Tasker
- Colorize gem installed (automatically added to development/test groups)
- Faraday gem available for HTTP API communication

**Sample Output:**
```
🔍 Tasker Jaeger Integration Validator
==================================================
Jaeger URL: http://localhost:16686
Validation Timeout: 30s

🚀 Starting Jaeger integration validation...
📡 Testing Jaeger connection... ✅ Connected (3 services discovered)

🔄 Executing sample workflows with tracing...
  🧪 Executing Linear dependency chain... ✅ Success (Trace: 1234567890123456...)
  🧪 Executing Diamond dependency pattern... ✅ Success (Trace: abcdef1234567890...)
  🧪 Executing Parallel execution pattern... ✅ Success (Trace: fedcba0987654321...)
  📊 Successfully executed 3/3 workflows

🔍 Analyzing collected traces...
  📋 Analyzing Linear dependency chain...     🔗 Span hierarchy: 4 spans, 3 parent-child relationships
      📋 step_validate_input (1366b5fb) → ee31cb1d
      📋 step_process_data (9cebcf9f) → ee31cb1d
      📋 step_generate_output (c1f36f36) → ee31cb1d
      📋 jaeger_validation_linear (ee31cb1d) ROOT
✅ Found (4 spans)
  📋 Analyzing Diamond dependency pattern...     🔗 Span hierarchy: 5 spans, 4 parent-child relationships
      📋 step_process_branch_a (98a4ce31) → cdf7729c
      📋 step_process_branch_b (840d232a) → cdf7729c
      📋 step_merge_results (10ad76b3) → cdf7729c
      📋 jaeger_validation_diamond (cdf7729c) ROOT
      📋 step_validate_input (c5911787) → cdf7729c
✅ Found (5 spans)
  📋 Analyzing Parallel execution pattern...     🔗 Span hierarchy: 4 spans, 3 parent-child relationships
      📋 step_process_parallel_1 (43d1ebe4) → 38a402b0
      📋 step_process_parallel_2 (894073c7) → 38a402b0
      📋 step_process_parallel_3 (0844788f) → 38a402b0
      📋 jaeger_validation_parallel (38a402b0) ROOT
✅ Found (4 spans)
  📊 Analyzed 3 traces with 13 total spans

📊 Analyzing performance metrics...
  ⏱️  Average span duration: 810.66ms
  📈 Total spans analyzed: 13

📋 Integration Validation Report
==================================================
🎉 Overall Status: PASSED

📝 Test Results:
  Jaeger Connection    ✅ PASS
  Workflow Execution   ✅ PASS
  Trace Collection     ✅ PASS
  Span Hierarchy       ✅ PASS
  Trace Correlation    ✅ PASS

📊 Performance Metrics:
  • Total Spans: 13
  • Average Duration: 810.66ms
  • Total Duration: 10538.64ms

🏆 Integration Status:
  ✅ Tasker is successfully integrated with Jaeger
  ✅ Distributed tracing is working correctly
  ✅ Span hierarchy and correlation are functioning
  ✅ Ready for production observability
```

### 🔍 `validate_prometheus_integration.rb` *(Coming in Week 2)*

Will validate Tasker's integration with Prometheus metrics collection.

**Planned Features:**
- **Metrics Endpoint Testing**: Validates `/tasker/metrics` endpoint
- **Prometheus API Integration**: Queries metrics via Prometheus HTTP API
- **Metric Structure Validation**: Validates labels, cardinality, and values
- **Alerting Rule Testing**: Tests compatibility with standard alerting rules
- **Dashboard Generation**: Creates sample Grafana dashboard queries

## Setup Instructions

### 1. Install Dependencies

The colorize gem is automatically included in development/test groups. Faraday is already available through Tasker's dependencies.

If you need to add them manually:
```ruby
# Gemfile
group :development, :test do
  gem 'colorize', '~> 1.1'  # For colored output
end
```

Run:
```bash
bundle install
```

### 2. Set Up Jaeger (Docker)

For local testing:
```bash
# Start Jaeger all-in-one
docker run -d \
  --name jaeger \
  -p 16686:16686 \
  -p 14268:14268 \
  jaegertracing/all-in-one:latest

# Verify Jaeger is running
curl http://localhost:16686/api/services
```

### 3. Configure OpenTelemetry

Ensure OpenTelemetry is properly configured in your Rails application:

```ruby
# config/initializers/opentelemetry.rb
require 'opentelemetry/sdk'
require 'opentelemetry/auto_instrumenter'
require 'opentelemetry/exporter/jaeger'

OpenTelemetry::SDK.configure do |c|
  c.service_name = 'tasker-demo'
  c.service_version = '2.5.0'

  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
      OpenTelemetry::Exporter::Jaeger::ThriftCollectorExporter.new(
        endpoint: 'http://localhost:14268/api/traces'
      )
    )
  )
end

OpenTelemetry::AutoInstrumenter.auto_instrument
```

### 4. Run Validation

```bash
# Navigate to Tasker project root
cd /path/to/tasker

# Run Jaeger validation
bundle exec rails runner scripts/validate_jaeger_integration.rb

# Check exit code
echo $?  # 0 = success, 1 = failure
```

## Enhanced Diagnostic Features

### Detailed Span Analysis

The script now provides comprehensive span hierarchy analysis with parent-child relationship mapping:

```
📋 step_validate_input (1366b5fb) → ee31cb1d
📋 step_process_data (9cebcf9f) → ee31cb1d
📋 step_generate_output (c1f36f36) → ee31cb1d
📋 jaeger_validation_linear (ee31cb1d) ROOT
```

Each span shows:
- **Operation name**: Descriptive span identifier
- **Span ID**: Unique 8-character identifier (truncated)
- **Parent relationship**: Arrow notation showing parent span ID or "ROOT"

### OpenTelemetry Diagnostics

When traces are not found, the script provides comprehensive diagnostic information:

```
🔍 OpenTelemetry Integration Diagnostics:
  📊 OpenTelemetry Tracer Provider: OpenTelemetry::SDK::Trace::TracerProvider
  📊 OpenTelemetry Exporter: OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor
  📊 Recent traces in Jaeger: 15
  📊 Services in Jaeger: tasker, demo-service
  📊 Trace flush status: Flush successful
```

### Error Handling Improvements

- **Robust exception handling**: All exceptions are properly caught and reported
- **Detailed error messages**: Specific HTTP status codes and error details
- **Actionable recommendations**: Specific steps to resolve common issues
- **Graceful degradation**: Script continues even if individual components fail

## Integration Patterns

### Workflow Patterns Tested

**Linear Workflow**:
```
validate_input → process_data → generate_output
```

**Diamond Workflow**:
```
validate_input → process_branch_a → merge_results
               → process_branch_b →
```

**Parallel Workflow**:
```
process_parallel_1
process_parallel_2  (concurrent execution)
process_parallel_3
```

### Validation Criteria

**Connection Testing**:
- ✅ Jaeger HTTP API accessibility
- ✅ Service discovery functionality
- ✅ Existing service detection

**Workflow Execution**:
- ✅ Successful workflow pattern execution
- ✅ Trace ID generation
- ✅ OpenTelemetry span creation

**Trace Collection**:
- ✅ Trace retrieval via Jaeger API
- ✅ Span data availability
- ✅ Trace persistence

**Span Hierarchy**:
- ✅ Root span identification
- ✅ Parent-child relationships
- ✅ Tasker-specific span detection

**Performance Analysis**:
- ✅ Span duration analysis
- ✅ Performance metrics calculation
- ✅ Timing validation

## Troubleshooting

### Common Issues

**Connection Failed**:
```
❌ Connection failed
Cannot connect to Jaeger: Connection refused
```
**Solution**: Ensure Jaeger is running and accessible at the specified URL.

**No Traces Found**:
```
⚠️ No trace data found
Traces may not have been collected yet
```
**Solution**: Check OpenTelemetry configuration and ensure spans are being exported.

**Span Hierarchy Issues**:
```
❌ No root span found
Pattern: linear_workflow
```
**Solution**: Verify OpenTelemetry instrumentation is properly configured.

### Debug Mode

For detailed debugging, modify the script to enable verbose output:

```ruby
# Add at the top of validate_jaeger_integration.rb
ENV['JAEGER_DEBUG'] = 'true'
```

## Production Deployment

### Recommended Setup

**Jaeger Configuration**:
- Use Jaeger with persistent storage (Elasticsearch/Cassandra)
- Configure appropriate retention policies
- Set up high availability deployment

**OpenTelemetry Configuration**:
- Use batch span processor for performance
- Configure sampling rates for production load
- Set appropriate resource attributes

**Monitoring**:
- Set up alerts for validation script failures
- Monitor trace collection rates
- Track span processing latency

### Continuous Validation

Add to your CI/CD pipeline:

```yaml
# .github/workflows/integration-validation.yml
name: Integration Validation

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  jaeger-integration:
    runs-on: ubuntu-latest

    services:
      jaeger:
        image: jaegertracing/all-in-one:latest
        ports:
          - 16686:16686
          - 14268:14268

    steps:
      - uses: actions/checkout@v3
      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true

      - name: Run Jaeger Integration Validation
        run: bundle exec rails runner scripts/validate_jaeger_integration.rb
```

## Development

### Adding New Validation Patterns

1. **Create new workflow pattern** in the `execute_sample_workflow` method
2. **Add pattern to workflow_patterns array**
3. **Implement specific validation logic**
4. **Update documentation**

### Extending Validation Criteria

1. **Add new validation methods**
2. **Update @validation_results structure**
3. **Include in overall success criteria**
4. **Add to reporting output**

## Support

For issues or questions about the integration validation scripts:

1. Check the troubleshooting section above
2. Review Jaeger and OpenTelemetry documentation
3. Verify Tasker configuration and setup
4. Check script logs for detailed error messages

---

**Tasker 2.5.0 Integration Validation Scripts**
*Proving production readiness through comprehensive observability testing*
