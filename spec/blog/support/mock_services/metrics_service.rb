# frozen_string_literal: true

require_relative 'base_mock_service'

# Mock Metrics Service (DataDog-like functionality)
# Simulates a metrics collection service for observability testing
class MockMetricsService < BaseMockService
  # Custom exceptions
  class TimeoutError < StandardError; end
  class AuthenticationError < StandardError; end
  class RateLimitError < StandardError; end

  class << self
    # Track metrics submissions
    def metrics_submitted
      @metrics_submitted ||= []
    end

    # Track metric types
    def metric_types
      @metric_types ||= {
        counters: [],
        histograms: [],
        gauges: [],
        timers: []
      }
    end

    def reset!
      super
      @metrics_submitted = []
      @metric_types = {
        counters: [],
        histograms: [],
        gauges: [],
        timers: []
      }
    end

    # Helper methods for test assertions
    def counter_submitted?(name, tags = {})
      metric_types[:counters].any? do |metric|
        metric[:name] == name && tags.all? { |k, v| metric[:tags][k] == v }
      end
    end

    def histogram_submitted?(name, tags = {})
      metric_types[:histograms].any? do |metric|
        metric[:name] == name && tags.all? { |k, v| metric[:tags][k] == v }
      end
    end

    def gauge_submitted?(name, tags = {})
      metric_types[:gauges].any? do |metric|
        metric[:name] == name && tags.all? { |k, v| metric[:tags][k] == v }
      end
    end

    def get_metric_values(name, metric_type = nil)
      metrics = metric_type ? metric_types[metric_type] : metrics_submitted
      metrics.select { |m| m[:name] == name }.map { |m| m[:value] }
    end
  end

  # Submit a counter metric
  # @param name [String] Metric name
  # @param value [Numeric] Counter value (default: 1)
  # @param tags [Hash] Metric tags
  # @param timestamp [Time] Metric timestamp (optional)
  def counter(name, value: 1, **tags)
    log_call(:counter, { name: name, value: value, tags: tags })
    
    metric = {
      name: name,
      value: value,
      tags: tags,
      timestamp: Time.current,
      type: :counter
    }
    
    self.class.metrics_submitted << metric
    self.class.metric_types[:counters] << metric
    
    handle_response(:counter, { status: 'ok', metric_id: generate_id('counter') })
  end

  # Submit a histogram metric
  # @param name [String] Metric name
  # @param value [Numeric] Histogram value
  # @param tags [Hash] Metric tags
  # @param timestamp [Time] Metric timestamp (optional)
  def histogram(name, value:, **tags)
    log_call(:histogram, { name: name, value: value, tags: tags })
    
    metric = {
      name: name,
      value: value,
      tags: tags,
      timestamp: Time.current,
      type: :histogram
    }
    
    self.class.metrics_submitted << metric
    self.class.metric_types[:histograms] << metric
    
    handle_response(:histogram, { status: 'ok', metric_id: generate_id('histogram') })
  end

  # Submit a gauge metric
  # @param name [String] Metric name
  # @param value [Numeric] Gauge value
  # @param tags [Hash] Metric tags
  # @param timestamp [Time] Metric timestamp (optional)
  def gauge(name, value:, **tags)
    log_call(:gauge, { name: name, value: value, tags: tags })
    
    metric = {
      name: name,
      value: value,
      tags: tags,
      timestamp: Time.current,
      type: :gauge
    }
    
    self.class.metrics_submitted << metric
    self.class.metric_types[:gauges] << metric
    
    handle_response(:gauge, { status: 'ok', metric_id: generate_id('gauge') })
  end

  # Submit a timer metric (histogram with time-specific semantics)
  # @param name [String] Metric name
  # @param value [Numeric] Timer value in seconds
  # @param tags [Hash] Metric tags
  def timer(name, value:, **tags)
    log_call(:timer, { name: name, value: value, tags: tags })
    
    metric = {
      name: name,
      value: value,
      tags: tags,
      timestamp: Time.current,
      type: :timer
    }
    
    self.class.metrics_submitted << metric
    self.class.metric_types[:timers] << metric
    
    handle_response(:timer, { status: 'ok', metric_id: generate_id('timer') })
  end

  # Time a block of code and submit as histogram
  # @param name [String] Metric name
  # @param tags [Hash] Metric tags
  # @param block [Proc] Code block to time
  def time(name, **tags, &block)
    start_time = Time.current
    result = block.call
    duration = Time.current - start_time
    
    histogram(name, value: duration, **tags)
    result
  end

  # Batch submit multiple metrics
  # @param metrics [Array<Hash>] Array of metric hashes
  def batch_submit(metrics)
    log_call(:batch_submit, { count: metrics.length })
    
    metrics.each do |metric|
      case metric[:type]
      when :counter
        counter(metric[:name], value: metric[:value], **metric[:tags])
      when :histogram
        histogram(metric[:name], value: metric[:value], **metric[:tags])
      when :gauge
        gauge(metric[:name], value: metric[:value], **metric[:tags])
      when :timer
        timer(metric[:name], value: metric[:value], **metric[:tags])
      end
    end
    
    handle_response(:batch_submit, {
      status: 'ok',
      submitted_count: metrics.length,
      batch_id: generate_id('batch')
    })
  end

  # Query metrics (for testing)
  # @param query [String] Metric query
  # @param time_range [Hash] Time range for query
  def query(query, time_range: { start: 1.hour.ago, end: Time.current })
    log_call(:query, { query: query, time_range: time_range })
    
    # Simple mock query - return metrics that match the query name
    matching_metrics = self.class.metrics_submitted.select do |metric|
      metric[:name].include?(query) &&
        metric[:timestamp] >= time_range[:start] &&
        metric[:timestamp] <= time_range[:end]
    end
    
    handle_response(:query, {
      status: 'ok',
      query: query,
      results: matching_metrics,
      count: matching_metrics.length
    })
  end

  # Health check for metrics service
  def health_check
    log_call(:health_check)
    
    handle_response(:health_check, {
      status: 'healthy',
      version: '2.1.0',
      uptime: '24h',
      metrics_processed: self.class.metrics_submitted.length
    })
  end
end

# Global metrics instance for easy access in tests
# This simulates having a global metrics client like DataDog.statsd
module Tasker
  def self.metrics
    @metrics ||= MockMetricsService.new
  end

  def self.reset_metrics!
    @metrics = MockMetricsService.new
    MockMetricsService.reset!
  end
end