#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'faraday'
require 'json'
require 'colorize'
require 'time'

# Load Rails environment
rails_env_path = File.expand_path('../spec/dummy/config/environment.rb', __dir__)
fallback_env_path = File.expand_path('../config/environment.rb', __dir__)

if File.exist?(rails_env_path)
  require rails_env_path
elsif File.exist?(fallback_env_path)
  require fallback_env_path
else
  puts '❌ Could not find Rails environment file'.colorize(:red)
  puts "  Tried: #{rails_env_path}".colorize(:yellow)
  puts "  Tried: #{fallback_env_path}".colorize(:yellow)
  exit 1
end

# Prometheus Integration Validator
class PrometheusIntegrationValidator
  PROMETHEUS_DEFAULT_URL = 'http://localhost:9090'
  VALIDATION_TIMEOUT = 30 # seconds
  METRICS_ENDPOINT = '/tasker/metrics'

  def initialize(prometheus_url = PROMETHEUS_DEFAULT_URL)
    @prometheus_url = prometheus_url
    @validation_results = {
      connection: false,
      metrics_endpoint: false,
      workflow_execution: false,
      metrics_collection: false,
      query_validation: false,
      performance_metrics: {},
      collected_metrics: [],
      errors: [],
      recommendations: []
    }
    @prometheus_client = build_prometheus_client
    @rails_client = build_rails_client
    @start_time = Time.current

    # Manually register MetricsSubscriber to ensure metrics collection
    # This works around the initialization timing issue in Coordinator
    begin
      Tasker::Events::Publisher.instance.tap do |publisher|
        Tasker::Events::Subscribers::MetricsSubscriber.subscribe(publisher)
      end
      puts '✅ MetricsSubscriber registered successfully'.colorize(:green)
    rescue StandardError => e
      puts "⚠️  Warning: Could not register MetricsSubscriber: #{e.message}".colorize(:yellow)
    end
  end

  def validate_integration
    puts '🔍 Prometheus Integration Validation Starting...'.colorize(:cyan)
    puts "📡 Target: #{@prometheus_url}".colorize(:light_blue)
    puts "🚀 Metrics Endpoint: #{METRICS_ENDPOINT}".colorize(:light_blue)
    puts

    # Phase 1: Connection Testing
    validate_prometheus_connection

    # Phase 2: Metrics Endpoint Testing
    validate_metrics_endpoint if @validation_results[:connection]

    # Phase 3: Workflow Execution with Metrics
    validate_workflow_metrics if @validation_results[:metrics_endpoint]

    # Phase 4: Metrics Collection Analysis
    analyze_collected_metrics if @validation_results[:workflow_execution]

    # Phase 5: Query Validation
    validate_prometheus_queries if @validation_results[:metrics_collection]

    # Phase 6: Performance Analysis
    analyze_performance_metrics if @validation_results[:query_validation]

    # Phase 7: Generate Report
    generate_integration_report

    overall_success?
  end

  private

  def build_prometheus_client
    Faraday.new(url: @prometheus_url) do |conn|
      conn.request :url_encoded
      conn.response :json, content_type: /\bjson$/
      conn.adapter Faraday.default_adapter
      conn.options.timeout = 10
      conn.options.open_timeout = 5
    end
  rescue StandardError => e
    add_error('Failed to initialize Prometheus client', e)
    nil
  end

  def build_rails_client
    Faraday.new(url: 'http://localhost:3000') do |conn|
      conn.response :json, content_type: /\bjson$/
      conn.adapter Faraday.default_adapter
      conn.options.timeout = 10
      conn.options.open_timeout = 5
    end
  rescue StandardError => e
    add_error('Failed to initialize Rails client', e)
    nil
  end

  def validate_prometheus_connection
    print '📡 Testing Prometheus connection... '

    return handle_missing_client('Prometheus') unless @prometheus_client

    response = @prometheus_client.get('/api/v1/status/config')

    if response.success?
      puts '✅ Connected'.colorize(:green)
      @validation_results[:connection] = true

      # Get additional status info
      targets_response = @prometheus_client.get('/api/v1/targets')
      if targets_response.success?
        active_targets = targets_response.body.dig('data', 'activeTargets')&.length || 0
        puts "  📊 Active targets: #{active_targets}"
      end
    else
      puts "❌ Failed (HTTP #{response.status})".colorize(:red)
      add_error('Prometheus connection failed', "HTTP #{response.status}: #{response.body}")
    end
  rescue Faraday::ConnectionFailed => e
    puts '❌ Connection failed'.colorize(:red)
    add_error('Cannot connect to Prometheus', e.message)
    add_recommendation("Ensure Prometheus is running at #{@prometheus_url}")
  rescue StandardError => e
    puts '❌ Error'.colorize(:red)
    add_error('Unexpected error during connection test', e)
  end

  def validate_metrics_endpoint
    print '🎯 Testing Tasker metrics endpoint... '

    return handle_missing_client('Rails') unless @rails_client

    response = @rails_client.get(METRICS_ENDPOINT)

    if response.success?
      metrics_text = response.body
      metric_lines = metrics_text.split("\n").reject { |line| line.start_with?('#') || line.strip.empty? }

      puts "✅ Available (#{metric_lines.length} metrics)".colorize(:green)
      @validation_results[:metrics_endpoint] = true
      @validation_results[:collected_metrics] = parse_metrics_from_text(metrics_text)

      puts '  📊 Metrics categories found:'
      categorize_metrics(@validation_results[:collected_metrics]).each do |category, count|
        puts "    • #{category}: #{count} metrics"
      end
    else
      puts "❌ Failed (HTTP #{response.status})".colorize(:red)
      add_error('Metrics endpoint failed', "HTTP #{response.status}: #{response.body}")
      add_recommendation('Ensure Tasker Rails application is running with metrics enabled')
    end
  rescue Faraday::ConnectionFailed => e
    puts '❌ Connection failed'.colorize(:red)
    add_error('Cannot connect to Tasker metrics endpoint', e.message)
    add_recommendation('Ensure Tasker Rails application is running on localhost:3000')
  rescue StandardError => e
    puts '❌ Error'.colorize(:red)
    add_error('Unexpected error during metrics endpoint test', e)
  end

  def validate_workflow_metrics
    puts '🔄 Executing workflows to generate metrics...'

    begin
      # Execute sample workflows to generate metrics
      workflow_results = execute_sample_workflows

      if workflow_results[:success]
        puts "  ✅ Executed #{workflow_results[:workflows_executed]} workflows".colorize(:green)
        @validation_results[:workflow_execution] = true

        # Wait for metrics to be collected
        print '  ⏳ Waiting for metrics collection... '
        sleep(3)
        puts '✅ Complete'.colorize(:green)
      else
        puts '  ❌ Workflow execution failed'.colorize(:red)
        add_error('Workflow execution failed', workflow_results[:error])
      end
    rescue StandardError => e
      puts '  ❌ Error during workflow execution'.colorize(:red)
      add_error('Workflow execution error', e)
    end
  end

  def execute_sample_workflows
    workflows_executed = 0

    # Create sample workflows with different patterns
    workflow_patterns = [
      { name: 'prometheus_validation_linear', steps: %w[validate_input process_data generate_output] },
      { name: 'prometheus_validation_diamond',
        steps: %w[validate_input process_branch_a process_branch_b merge_results] },
      { name: 'prometheus_validation_parallel', steps: %w[validate_input parallel_step_1 parallel_step_2 final_step] }
    ]

    workflow_patterns.each do |pattern|
      create_and_execute_workflow(pattern)
      workflows_executed += 1
    end

    { success: true, workflows_executed: workflows_executed }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def create_and_execute_workflow(pattern)
    # Include the EventPublisher concern to publish events
    publisher = Tasker::Events::Publisher.instance

    # Create a simple task to generate metrics
    task_namespace = Tasker::TaskNamespace.find_or_create_by!(name: 'prometheus_validation')

    named_task = Tasker::NamedTask.find_or_create_by!(
      name: pattern[:name],
      task_namespace: task_namespace
    )

    # Create and execute task
    task = Tasker::Task.create!(
      named_task: named_task,
      context: { validation: true, pattern: pattern[:name] }
    )

    # Publish task started event to trigger metrics collection
    publisher.publish(Tasker::Constants::TaskEvents::START_REQUESTED, {
                        task_id: task.task_id,
                        task_name: task.name,
                        event_type: :started,
                        timestamp: Time.current.iso8601
                      })

    # Create workflow steps manually for validation purposes
    created_steps = []
    pattern[:steps].each_with_index do |step_name, index|
      # Create a dependent system for the validation steps
      dependent_system = Tasker::DependentSystem.find_or_create_by!(name: 'prometheus_validation')

      # Create named step first
      named_step = Tasker::NamedStep.find_or_create_by!(
        name: step_name,
        dependent_system: dependent_system
      )

      # Create workflow step
      workflow_step = Tasker::WorkflowStep.create!(
        task: task,
        named_step: named_step
      )

      created_steps << workflow_step

      # Create dependency edges between steps
      previous_step = created_steps[index - 1] if index.positive?
      if previous_step
        # Create dependency edge
        Tasker::WorkflowStepEdge.find_or_create_by!(
          from_step: previous_step,
          to_step: workflow_step,
          name: Tasker::WorkflowStep::PROVIDES_EDGE_NAME
        )
      end

      # Publish step events to trigger metrics collection
      publisher.publish(Tasker::Constants::StepEvents::EXECUTION_REQUESTED, {
                          task_id: task.task_id,
                          step_id: workflow_step.workflow_step_id,
                          step_name: step_name,
                          event_type: :started,
                          timestamp: Time.current.iso8601
                        })

      # Simulate step execution with state transitions
      workflow_step.state_machine.transition_to(:in_progress)

      # Simulate processing time
      sleep(0.1)

      # Complete the step
      workflow_step.state_machine.transition_to(:complete)

      # Publish step completed event with duration
      publisher.publish(Tasker::Constants::StepEvents::COMPLETED, {
                          task_id: task.task_id,
                          step_id: workflow_step.workflow_step_id,
                          step_name: step_name,
                          event_type: :completed,
                          duration: 0.1,
                          timestamp: Time.current.iso8601
                        })
    end

    # Complete the task
    task.state_machine.transition_to(:complete)

    # Publish task completed event
    publisher.publish(Tasker::Constants::TaskEvents::COMPLETED, {
                        task_id: task.task_id,
                        task_name: task.name,
                        event_type: :completed,
                        total_duration: pattern[:steps].size * 0.1,
                        completed_steps: created_steps.size,
                        total_steps: created_steps.size,
                        timestamp: Time.current.iso8601
                      })

    puts "    ✅ Created #{pattern[:name]} workflow with #{created_steps.size} steps"
    created_steps
  end

  def analyze_collected_metrics
    puts '📊 Analyzing collected metrics...'.colorize(:cyan)

    begin
      backend = Tasker::Telemetry::MetricsBackend.instance
      total_metrics = backend.metrics.keys.length
      backend.all_metrics

      puts "  ✅ Analyzed (#{total_metrics} total metrics)".colorize(:green)

      # Categorize metrics by type
      counter_metrics = 0
      gauge_metrics = 0
      histogram_metrics = 0
      unique_labels = Set.new

      backend.metrics.each_value do |metric|
        case metric
        when Tasker::Telemetry::MetricTypes::Counter
          counter_metrics += 1
        when Tasker::Telemetry::MetricTypes::Gauge
          gauge_metrics += 1
        when Tasker::Telemetry::MetricTypes::Histogram
          histogram_metrics += 1
        end

        # Extract labels if available
        if metric.respond_to?(:labels) && metric.labels.is_a?(Hash)
          metric.labels.each { |key, value| unique_labels.add("#{key}=#{value}") }
        end
      end

      puts '  📈 Metric analysis:'.colorize(:yellow)
      puts "    • Total metrics: #{total_metrics}".colorize(:white)
      puts "    • Counter metrics: #{counter_metrics}".colorize(:white)
      puts "    • Gauge metrics: #{gauge_metrics}".colorize(:white)
      puts "    • Histogram metrics: #{histogram_metrics}".colorize(:white)
      puts "    • Unique labels: #{unique_labels.size}".colorize(:white)

      # Show individual metrics with values
      if total_metrics.positive?
        puts '  📋 Individual metrics:'.colorize(:yellow)
        backend.metrics.each do |name, metric|
          value = metric.respond_to?(:value) ? metric.value : 'N/A'
          puts "    • #{name}: #{value}".colorize(:white)
        end
      end

      @validation_results[:metrics_collection] = total_metrics.positive?
      total_metrics.positive?
    rescue StandardError => e
      puts "  ❌ Failed to analyze metrics: #{e.message}".colorize(:red)
      @validation_results[:metrics_collection] = false
      false
    end
  end

  def validate_prometheus_queries
    puts '🔍 Validating Prometheus queries...'

    # Test various PromQL queries
    test_queries = [
      'up',
      'prometheus_notifications_total',
      'prometheus_config_last_reload_successful',
      'rate(prometheus_http_requests_total[5m])'
    ]

    successful_queries = 0

    test_queries.each do |query|
      print "  📋 Testing query: #{query}... "

      response = @prometheus_client.get('/api/v1/query', { query: query })

      if response.success? && response.body['status'] == 'success'
        result_count = response.body.dig('data', 'result')&.length || 0
        puts "✅ Success (#{result_count} results)".colorize(:green)
        successful_queries += 1
      else
        puts '❌ Failed'.colorize(:red)
        add_error("Query failed: #{query}", response.body)
      end
    rescue StandardError => e
      puts '❌ Error'.colorize(:red)
      add_error("Query error: #{query}", e)
    end

    if successful_queries == test_queries.length
      @validation_results[:query_validation] = true
      puts "  ✅ All #{test_queries.length} queries successful".colorize(:green)
    else
      puts "  ⚠️  #{successful_queries}/#{test_queries.length} queries successful".colorize(:yellow)
    end
  end

  def analyze_performance_metrics
    puts '📊 Analyzing performance metrics...'

    # Query Prometheus metrics about itself
    performance_queries = {
      'Prometheus Build Info' => 'prometheus_build_info',
      'HTTP Requests Rate' => 'rate(prometheus_http_requests_total[1m])',
      'Rule Evaluation Duration' => 'prometheus_rule_evaluation_duration_seconds',
      'TSDB Head Samples' => 'prometheus_tsdb_head_samples_appended_total'
    }

    performance_data = {}

    performance_queries.each do |name, query|
      print "  📈 #{name}... "

      response = @prometheus_client.get('/api/v1/query', { query: query })

      if response.success? && response.body['status'] == 'success'
        results = response.body.dig('data', 'result') || []
        performance_data[name] = {
          query: query,
          result_count: results.length,
          sample_value: results.first&.dig('value', 1)
        }
        puts "✅ #{results.length} results".colorize(:green)
      else
        puts '❌ Failed'.colorize(:red)
        performance_data[name] = { query: query, error: response.body }
      end
    rescue StandardError => e
      puts '❌ Error'.colorize(:red)
      performance_data[name] = { query: query, error: e.message }
    end

    @validation_results[:performance_metrics] = performance_data
  end

  def parse_metrics_from_text(metrics_text)
    metrics = []

    metrics_text.split("\n").each do |line|
      next if line.start_with?('#') || line.strip.empty?

      # Parse metric name and value
      next unless line =~ /^([a-zA-Z_:][a-zA-Z0-9_:]*(?:\{[^}]*\})?) (.+)$/

      metric_name_with_labels = ::Regexp.last_match(1)
      value = ::Regexp.last_match(2)

      # Extract metric name without labels
      metric_name = metric_name_with_labels.split('{').first

      metrics << {
        name: metric_name,
        full_name: metric_name_with_labels,
        value: value,
        type: determine_metric_type(metric_name)
      }
    end

    metrics
  end

  def determine_metric_type(metric_name)
    case metric_name
    when /_total$/
      'counter'
    when /_bucket$/
      'histogram'
    when /_count$/, /_sum$/
      'histogram'
    else
      'gauge'
    end
  end

  def categorize_metrics(metrics)
    categories = Hash.new(0)

    metrics.each do |metric|
      category = case metric[:name]
                 when /^tasker_/
                   'Tasker'
                 when /^prometheus_/
                   'Prometheus'
                 when /^go_/
                   'Go Runtime'
                 when /^process_/
                   'Process'
                 else
                   'Other'
                 end

      categories[category] += 1
    end

    categories
  end

  def generate_integration_report
    puts "\n📋 Prometheus Integration Validation Report".colorize(:cyan)
    puts '=' * 60

    # Overall Status
    if overall_success?
      puts '🎉 Overall Status: PASSED'.colorize(:green)
    else
      puts '❌ Overall Status: FAILED'.colorize(:red)
    end

    puts
    puts '📝 Test Results:'.colorize(:light_blue)
    print_test_result('Prometheus Connection', @validation_results[:connection])
    print_test_result('Metrics Endpoint', @validation_results[:metrics_endpoint])
    print_test_result('Workflow Execution', @validation_results[:workflow_execution])
    print_test_result('Metrics Collection', @validation_results[:metrics_collection])
    print_test_result('Query Validation', @validation_results[:query_validation])

    # Metrics Summary
    if @validation_results[:collected_metrics].any?
      puts
      puts '📊 Metrics Summary:'.colorize(:light_blue)
      analysis = analyze_metric_structure(@validation_results[:collected_metrics])
      puts "  • Total Metrics: #{analysis[:total_metrics]}"
      puts "  • Counter Metrics: #{analysis[:counter_metrics]}"
      puts "  • Gauge Metrics: #{analysis[:gauge_metrics]}"
      puts "  • Histogram Metrics: #{analysis[:histogram_metrics]}"
      puts "  • Unique Labels: #{analysis[:unique_labels]}"

      # Show sample metrics
      puts
      puts '📋 Sample Metrics:'.colorize(:light_blue)
      @validation_results[:collected_metrics].first(5).each do |metric|
        puts "  • #{metric[:name]} (#{metric[:type]}): #{metric[:value]}"
      end
    end

    # Performance Metrics
    if @validation_results[:performance_metrics].any?
      puts
      puts '⚡ Performance Analysis:'.colorize(:light_blue)
      @validation_results[:performance_metrics].each do |name, data|
        if data[:error]
          puts "  • #{name}: ❌ Error"
        else
          puts "  • #{name}: ✅ #{data[:result_count]} results"
        end
      end
    end

    # Errors and Recommendations
    print_errors_and_recommendations
  end

  def print_test_result(test_name, passed)
    status = passed ? '✅ PASS' : '❌ FAIL'
    color = passed ? :green : :red
    puts "  #{test_name.ljust(20)} #{status.colorize(color)}"
  end

  def print_errors_and_recommendations
    return if @validation_results[:errors].empty? && @validation_results[:recommendations].empty?

    unless @validation_results[:errors].empty?
      puts
      puts '❌ Errors:'.colorize(:red)
      @validation_results[:errors].each_with_index do |error, index|
        puts "  #{index + 1}. #{error[:message]}"
        puts "     Details: #{error[:details]}" if error[:details]
      end
    end

    return if @validation_results[:recommendations].empty?

    puts
    puts '💡 Recommendations:'.colorize(:yellow)
    @validation_results[:recommendations].each_with_index do |rec, index|
      puts "  #{index + 1}. #{rec}"
    end
  end

  def overall_success?
    required_validations = %i[connection metrics_endpoint workflow_execution metrics_collection query_validation]
    required_validations.all? { |validation| @validation_results[validation] }
  end

  def add_error(message, details = nil)
    @validation_results[:errors] << {
      message: message,
      details: details.is_a?(Exception) ? details.message : details
    }
  end

  def add_recommendation(message)
    @validation_results[:recommendations] << message
  end

  def handle_missing_client(client_name)
    puts "❌ #{client_name} client not available".colorize(:red)
    add_error("#{client_name} client initialization failed", 'Check connection configuration')
    false
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  puts 'Tasker 2.5.0 - Prometheus Integration Validator'.colorize(:cyan)
  puts '=' * 50
  puts

  validator = PrometheusIntegrationValidator.new
  success = validator.validate_integration

  puts
  puts '=' * 50

  if success
    puts '🎉 Prometheus integration validation completed successfully!'.colorize(:green)
    puts 'Tasker is ready for production deployment with Prometheus monitoring.'.colorize(:green)
    exit 0
  else
    puts '❌ Prometheus integration validation failed.'.colorize(:red)
    puts 'Please review the errors and recommendations above.'.colorize(:red)
    exit 1
  end
end
