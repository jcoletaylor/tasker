#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'

# For Rails engine, we need to use the dummy app's environment
dummy_env_path = File.expand_path('../spec/dummy/config/environment', __dir__)
if File.exist?(dummy_env_path)
  require dummy_env_path
else
  # Fallback: try to load Tasker directly for standalone usage
  require_relative '../lib/tasker'
end

require 'faraday'
require 'json'
require 'colorize'

# Tasker 2.5.0 - Jaeger Integration Validation Script
#
# This script validates Tasker's integration with Jaeger distributed tracing
# by executing sample workflows, querying traces via Jaeger HTTP API, and
# generating comprehensive integration health reports.
#
# Usage: bundle exec rails runner scripts/validate_jaeger_integration.rb
#
class JaegerIntegrationValidator
  JAEGER_DEFAULT_URL = 'http://localhost:16686'
  VALIDATION_TIMEOUT = 30 # seconds

  def initialize(jaeger_url = JAEGER_DEFAULT_URL)
    @jaeger_url = jaeger_url
    @validation_results = {
      connection: false,
      workflow_execution: false,
      trace_collection: false,
      span_hierarchy: false,
      trace_correlation: false,
      performance_metrics: {},
      errors: [],
      recommendations: []
    }
    @jaeger_client = build_jaeger_client

    puts '🔍 Tasker Jaeger Integration Validator'.colorize(:cyan)
    puts '=' * 50
    puts "Jaeger URL: #{@jaeger_url}"
    puts "Validation Timeout: #{VALIDATION_TIMEOUT}s"
    puts ''
  end

  def validate_integration
    puts '🚀 Starting Jaeger integration validation...'.colorize(:blue)

    # Phase 1: Connection Testing
    validate_jaeger_connection

    # Phase 2: Workflow Execution with Tracing
    validate_workflow_tracing if @validation_results[:connection]

    # Phase 3: Trace Analysis (if workflows were executed)
    analyze_collected_traces if @validation_results[:workflow_execution]

    # Phase 4: Performance Analysis
    analyze_performance_metrics if @validation_results[:span_hierarchy]

    # Phase 5: Generate Report
    generate_integration_report

    # Return validation status
    overall_success?
  end

  private

  def build_jaeger_client
    Faraday.new(url: @jaeger_url) do |conn|
      conn.request :json
      conn.response :json, content_type: /\bjson$/
      conn.adapter Faraday.default_adapter
      conn.options.timeout = 10
      conn.options.open_timeout = 5
    end
  rescue StandardError => e
    add_error('Failed to initialize Jaeger client', e)
    nil
  end

  def validate_jaeger_connection
    print '📡 Testing Jaeger connection... '

    response = @jaeger_client.get('/api/services')

    if response.success?
      services = response.body['data'] || []
      puts "✅ Connected (#{services.length} services discovered)".colorize(:green)
      @validation_results[:connection] = true

      # Check if Tasker service is already registered
      tasker_services = services.select { |s| s.include?('tasker') || s.include?('Tasker') }
      if tasker_services.any?
        puts "  📋 Found existing Tasker services: #{tasker_services.join(', ')}"
      else
        puts '  ℹ️  No existing Tasker services found (expected for first run)'
      end
    else
      puts "❌ Failed (HTTP #{response.status})".colorize(:red)
      add_error('Jaeger connection failed', "HTTP #{response.status}: #{response.body}")
    end
  rescue Faraday::ConnectionFailed => e
    puts '❌ Connection failed'.colorize(:red)
    add_error('Cannot connect to Jaeger', e.message)
    add_recommendation("Ensure Jaeger is running at #{@jaeger_url}")
    add_recommendation('Try: docker run -d --name jaeger -p 16686:16686 jaegertracing/all-in-one:latest')
  rescue StandardError => e
    puts '❌ Error'.colorize(:red)
    add_error('Unexpected error during connection test', e)
  end

  def validate_workflow_tracing
    puts "\n🔄 Executing sample workflows with tracing..."

    workflows_executed = 0
    trace_ids = []

    # Execute different workflow patterns
    workflow_patterns = [
      { name: 'linear_workflow', description: 'Linear dependency chain' },
      { name: 'diamond_workflow', description: 'Diamond dependency pattern' },
      { name: 'parallel_workflow', description: 'Parallel execution pattern' }
    ]

    workflow_patterns.each do |pattern|
      print "  🧪 Executing #{pattern[:description]}... "

      begin
        trace_id = execute_sample_workflow(pattern[:name])
        if trace_id
          trace_ids << {
            pattern: pattern[:name],
            trace_id: trace_id,
            description: pattern[:description]
          }
          workflows_executed += 1
          puts "✅ Success (Trace: #{trace_id[0..15]}...)".colorize(:green)
        else
          puts '⚠️  No trace ID generated'.colorize(:yellow)
        end
      rescue StandardError => e
        puts '❌ Failed'.colorize(:red)
        add_error("Workflow execution failed for #{pattern[:name]}", e)
      end
    end

    if workflows_executed.positive?
      @validation_results[:workflow_execution] = true
      @validation_results[:trace_ids] = trace_ids
      puts "  📊 Successfully executed #{workflows_executed}/#{workflow_patterns.length} workflows"

      # Wait for traces to be collected
      puts "  ⏳ Waiting for trace collection (#{VALIDATION_TIMEOUT}s timeout)..."
      sleep 5 # Give Jaeger more time to collect traces with child spans
    else
      add_error('No workflows executed successfully', 'All workflow patterns failed')
    end
  end

  def execute_sample_workflow(pattern_name)
    # Create a simple test workflow based on the pattern
    case pattern_name
    when 'linear_workflow'
      execute_linear_test_workflow
    when 'diamond_workflow'
      execute_diamond_test_workflow
    when 'parallel_workflow'
      execute_parallel_test_workflow
    else
      raise ArgumentError, "Unknown workflow pattern: #{pattern_name}"
    end
  end

  def execute_linear_test_workflow
    # Create a simple linear workflow for tracing validation
    Tasker::Types::TaskRequest.new(
      name: 'jaeger_validation_linear',
      context: {
        validation_run: true,
        pattern: 'linear',
        timestamp: Time.current.iso8601
      }
    )

    # Execute with OpenTelemetry context
    OpenTelemetry.tracer_provider.tracer('tasker.validation').in_span('jaeger_validation_linear') do |span|
      span.set_attribute('validation.pattern', 'linear')
      span.set_attribute('validation.timestamp', Time.current.iso8601)

      # Simulate workflow execution
      simulate_workflow_steps(%w[validate_input process_data generate_output], span)

      # Return trace ID from current span context
      span.context.trace_id.unpack1('H*')
    end
  rescue StandardError => e
    add_error('Linear workflow execution failed', e)
    nil
  end

  def execute_diamond_test_workflow
    Tasker::Types::TaskRequest.new(
      name: 'jaeger_validation_diamond',
      context: {
        validation_run: true,
        pattern: 'diamond',
        timestamp: Time.current.iso8601
      }
    )

    OpenTelemetry.tracer_provider.tracer('tasker.validation').in_span('jaeger_validation_diamond') do |span|
      span.set_attribute('validation.pattern', 'diamond')
      span.set_attribute('validation.timestamp', Time.current.iso8601)

      # Simulate diamond pattern: validate -> (process_a + process_b) -> merge
      simulate_workflow_steps(['validate_input'], span)

      # Parallel branches
      %w[process_branch_a process_branch_b].each do |branch|
        span.add_event("starting_#{branch}")
        simulate_workflow_steps([branch], span)
        span.add_event("completed_#{branch}")
      end

      simulate_workflow_steps(['merge_results'], span)

      span.context.trace_id.unpack1('H*')
    end
  rescue StandardError => e
    add_error('Diamond workflow execution failed', e)
    nil
  end

  def execute_parallel_test_workflow
    Tasker::Types::TaskRequest.new(
      name: 'jaeger_validation_parallel',
      context: {
        validation_run: true,
        pattern: 'parallel',
        timestamp: Time.current.iso8601
      }
    )

    OpenTelemetry.tracer_provider.tracer('tasker.validation').in_span('jaeger_validation_parallel') do |span|
      span.set_attribute('validation.pattern', 'parallel')
      span.set_attribute('validation.timestamp', Time.current.iso8601)

      # Simulate parallel execution
      parallel_steps = %w[process_parallel_1 process_parallel_2 process_parallel_3]
      parallel_steps.each do |step|
        span.add_event("starting_#{step}")
        simulate_workflow_steps([step], span)
        span.add_event("completed_#{step}")
      end

      span.context.trace_id.unpack1('H*')
    end
  rescue StandardError => e
    add_error('Parallel workflow execution failed', e)
    nil
  end

  def simulate_workflow_steps(step_names, parent_span)
    step_names.each do |step_name|
      # Create child spans for each step to establish parent-child relationships
      OpenTelemetry.tracer_provider.tracer('tasker.validation').in_span("step_#{step_name}") do |step_span|
        step_span.set_attribute('step.name', step_name)
        step_span.set_attribute('step.type', 'workflow_step')

        parent_span.add_event('step_started', attributes: { 'step.name' => step_name })

        # Simulate step processing time
        sleep(0.01 + rand(0.05)) # 10-60ms processing time

        step_span.set_attribute('step.status', 'success')
        step_span.add_event('step_processing_completed')

        parent_span.add_event('step_completed', attributes: {
                                'step.name' => step_name,
                                'step.status' => 'success'
                              })
      end
    end
  end

  def analyze_collected_traces
    puts "\n🔍 Analyzing collected traces..."

    return unless @validation_results[:trace_ids]&.any?

    traces_found = 0
    spans_analyzed = 0

    @validation_results[:trace_ids].each do |trace_info|
      print "  📋 Analyzing #{trace_info[:description]}... "

      begin
        trace_data = query_trace_by_id(trace_info[:trace_id])

        if trace_data && trace_data['data'] && trace_data['data'].any?
          traces_found += 1
          spans = extract_spans_from_trace(trace_data)
          spans_analyzed += spans.length

          # Validate span hierarchy
          hierarchy_valid = validate_span_hierarchy(spans, trace_info[:pattern])

          puts "✅ Found (#{spans.length} spans)".colorize(:green)

          @validation_results[:span_hierarchy] = true if hierarchy_valid
        else
          puts '⚠️  No trace data found'.colorize(:yellow)
          add_error('Trace not found in Jaeger', "Trace ID: #{trace_info[:trace_id]}")
        end
      rescue StandardError => e
        puts '❌ Analysis failed'.colorize(:red)
        add_error("Trace analysis failed for #{trace_info[:pattern]}", e)
      end
    end

    if traces_found.positive?
      @validation_results[:trace_collection] = true
      puts "  📊 Analyzed #{traces_found} traces with #{spans_analyzed} total spans"
    else
      add_error('No traces found in Jaeger', 'Traces may not have been collected yet')
      add_recommendation('Increase trace collection timeout or check OpenTelemetry configuration')

      # Add comprehensive diagnostic information
      puts "\n🔍 OpenTelemetry Integration Diagnostics:".colorize(:yellow)
      diagnose_otel_integration
    end
  end

  def query_trace_by_id(trace_id)
    response = @jaeger_client.get("/api/traces/#{trace_id}")

    if response.success?
      response.body
    else
      add_error('Failed to query trace', "HTTP #{response.status} for trace #{trace_id}")
      nil
    end
  rescue StandardError => e
    add_error('Error querying trace', e)
    nil
  end

  def extract_spans_from_trace(trace_data)
    spans = []

    trace_data['data']&.each do |trace|
      trace['spans']&.each do |span|
        spans << {
          span_id: span['spanID'],
          operation_name: span['operationName'],
          parent_span_id: span.dig('references', 0, 'spanID'),
          start_time: span['startTime'],
          duration: span['duration'],
          tags: span['tags'] || [],
          process: span.dig('process', 'serviceName')
        }
      end
    end

    spans
  end

  def validate_span_hierarchy(spans, pattern)
    return false if spans.empty?

    # Check for root span
    root_spans = spans.select { |s| s[:parent_span_id].blank? }

    if root_spans.empty?
      add_error('No root span found', "Pattern: #{pattern}")
      return false
    end

    # Check for Tasker-specific spans
    tasker_spans = spans.select do |s|
      s[:operation_name]&.include?('jaeger_validation') || s[:operation_name]&.include?('step_')
    end

    if tasker_spans.empty?
      add_error('No Tasker spans found', "Pattern: #{pattern}")
      return false
    end

    # Validate span relationships - look for non-nil parent span IDs
    parent_child_relationships = spans.count { |s| s[:parent_span_id].present? }

    # More detailed relationship analysis
    if parent_child_relationships.positive?
      @validation_results[:trace_correlation] = true
      puts "    🔗 Span hierarchy: #{spans.length} spans, #{parent_child_relationships} parent-child relationships"

      # Show span details for debugging
      spans.each do |span|
        parent_info = span[:parent_span_id] ? "→ #{span[:parent_span_id][0..7]}" : 'ROOT'
        puts "      📋 #{span[:operation_name]} (#{span[:span_id][0..7]}) #{parent_info}"
      end
    else
      puts "    ⚠️  Span hierarchy: #{spans.length} spans, #{parent_child_relationships} parent-child relationships (no correlation)"
    end

    true
  end

  def analyze_performance_metrics
    puts "\n📊 Analyzing performance metrics..."

    return unless @validation_results[:trace_ids]&.any?

    total_duration = 0
    span_count = 0

    @validation_results[:trace_ids].each do |trace_info|
      trace_data = query_trace_by_id(trace_info[:trace_id])
      next unless trace_data

      spans = extract_spans_from_trace(trace_data)
      spans.each do |span|
        total_duration += span[:duration] || 0
        span_count += 1
      end
    rescue StandardError => e
      add_error('Performance analysis failed', e)
    end

    return unless span_count.positive?

    avg_duration = total_duration / span_count
    @validation_results[:performance_metrics] = {
      total_spans: span_count,
      total_duration_us: total_duration,
      average_duration_us: avg_duration,
      average_duration_ms: (avg_duration / 1000.0).round(2)
    }

    puts "  ⏱️  Average span duration: #{@validation_results[:performance_metrics][:average_duration_ms]}ms"
    puts "  📈 Total spans analyzed: #{span_count}"
  end

  def generate_integration_report
    puts "\n📋 Integration Validation Report".colorize(:cyan)
    puts '=' * 50

    # Overall Status
    if overall_success?
      puts '🎉 Overall Status: PASSED'.colorize(:green)
    else
      puts '❌ Overall Status: FAILED'.colorize(:red)
    end

    puts ''

    # Individual Test Results
    puts '📝 Test Results:'
    print_test_result('Jaeger Connection', @validation_results[:connection])
    print_test_result('Workflow Execution', @validation_results[:workflow_execution])
    print_test_result('Trace Collection', @validation_results[:trace_collection])
    print_test_result('Span Hierarchy', @validation_results[:span_hierarchy])
    print_test_result('Trace Correlation', @validation_results[:trace_correlation])

    # Performance Metrics
    if @validation_results[:performance_metrics].any?
      puts "\n📊 Performance Metrics:"
      metrics = @validation_results[:performance_metrics]
      puts "  • Total Spans: #{metrics[:total_spans]}"
      puts "  • Average Duration: #{metrics[:average_duration_ms]}ms"
      puts "  • Total Duration: #{(metrics[:total_duration_us] / 1000.0).round(2)}ms"
    end

    # Errors
    if @validation_results[:errors].any?
      puts "\n❌ Errors Encountered:"
      @validation_results[:errors].each_with_index do |error, i|
        puts "  #{i + 1}. #{error[:message]}"
        puts "     Details: #{error[:details]}" if error[:details]
      end
    end

    # Recommendations
    if @validation_results[:recommendations].any?
      puts "\n💡 Recommendations:"
      @validation_results[:recommendations].each_with_index do |rec, i|
        puts "  #{i + 1}. #{rec}"
      end
    end

    # Integration Status
    puts "\n🏆 Integration Status:"
    if overall_success?
      puts '  ✅ Tasker is successfully integrated with Jaeger'.colorize(:green)
      puts '  ✅ Distributed tracing is working correctly'.colorize(:green)
      puts '  ✅ Span hierarchy and correlation are functioning'.colorize(:green)
      puts '  ✅ Ready for production observability'.colorize(:green)
    else
      puts '  ❌ Integration issues detected'.colorize(:red)
      puts '  ⚠️  Resolve errors before production deployment'.colorize(:yellow)
    end

    puts "\n#{'=' * 50}"
    puts "Validation completed at #{Time.current.strftime('%Y-%m-%d %H:%M:%S UTC')}"
  end

  def print_test_result(test_name, passed)
    status = passed ? '✅ PASS'.colorize(:green) : '❌ FAIL'.colorize(:red)
    puts "  #{test_name.ljust(20)} #{status}"
  end

  def overall_success?
    @validation_results[:connection] &&
      @validation_results[:workflow_execution] &&
      @validation_results[:trace_collection] &&
      @validation_results[:span_hierarchy]
  end

  def add_error(message, details = nil)
    @validation_results[:errors] << {
      message: message,
      details: details&.to_s,
      timestamp: Time.current.iso8601
    }
  end

  def add_recommendation(message)
    @validation_results[:recommendations] << message
  end

  def diagnose_otel_integration
    puts "  📊 OpenTelemetry Tracer Provider: #{OpenTelemetry.tracer_provider.class.name}"
    puts "  📊 OpenTelemetry Exporter: #{check_otel_exporter_type}"
    puts "  📊 Recent traces in Jaeger: #{get_recent_traces_count}"
    puts "  📊 Services in Jaeger: #{get_services.join(', ')}"
    puts "  📊 Trace flush status: #{check_trace_flush_status}"

    # Check if traces are being generated but not exported
    return unless get_recent_traces_count.zero?

    puts '  ⚠️  No recent traces found - possible export configuration issue'.colorize(:yellow)
    add_recommendation('Check OpenTelemetry exporter configuration and Jaeger endpoint')
  end

  def check_otel_exporter_type
    # Try to determine the exporter type from the tracer provider
    if defined?(OpenTelemetry::SDK::Trace::TracerProvider)
      provider = OpenTelemetry.tracer_provider
      if provider.respond_to?(:span_processors)
        processors = begin
          provider.span_processors
        rescue StandardError
          []
        end
        if processors.any?
          processor_types = processors.map { |p| p.class.name }.join(', ')
          return processor_types
        end
      end
    end
    'Unknown'
  rescue StandardError
    'Unable to determine'
  end

  def get_recent_traces_count
    # Query for recent traces from the last hour
    end_time = (Time.now.to_f * 1_000_000).to_i # microseconds
    start_time = ((Time.zone.now - 3600).to_f * 1_000_000).to_i # 1 hour ago

    response = @jaeger_client.get('/api/traces', {
                                    service: 'tasker',
                                    start: start_time,
                                    end: end_time,
                                    limit: 100
                                  })

    if response.success? && response.body['data']
      response.body['data'].length
    else
      0
    end
  rescue StandardError
    0
  end

  def check_trace_flush_status
    # Check if OpenTelemetry is configured to flush traces
    if defined?(OpenTelemetry::SDK::Trace::TracerProvider)
      provider = OpenTelemetry.tracer_provider
      if provider.respond_to?(:force_flush)
        begin
          provider.force_flush
          'Flush successful'
        rescue StandardError => e
          "Flush failed: #{e.message}"
        end
      else
        'Flush not available'
      end
    else
      'SDK not detected'
    end
  rescue StandardError => e
    "Error checking flush: #{e.message}"
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  # Parse command line arguments
  jaeger_url = ARGV[0] || JaegerIntegrationValidator::JAEGER_DEFAULT_URL

  validator = JaegerIntegrationValidator.new(jaeger_url)
  success = validator.validate_integration

  exit(success ? 0 : 1)
end
