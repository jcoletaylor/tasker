# frozen_string_literal: true

# This is a simple in-memory adapter for telemetry.
# It's used for testing and development.
# It's not used in production.

class MemoryAdapter < Tasker::Observability::Adapter
  attr_reader :recorded_events, :traces, :spans

  def initialize
    super
    @recorded_events = []
    @traces = []
    @current_trace = nil
    @spans = []
  end

  def record(event, payload = {})
    @recorded_events << { event: event, payload: payload }
  end

  def start_trace(name, attributes = {})
    @current_trace = { name: name, attributes: attributes, started_at: Time.current }
    @traces << @current_trace
  end

  def end_trace
    return unless @current_trace

    @current_trace[:ended_at] = Time.current
    @current_trace = nil
  end

  def add_span(name, attributes = {}, &)
    # Create and store the span
    span = { name: name, attributes: attributes, started_at: Time.current }

    # Execute the block safely
    result = nil
    begin
      result = yield if block_given?
    rescue StandardError => e
      # If an error occurs during the block execution, mark the span as errored
      # but don't re-raise the exception since this is just for observability
      span[:error] = e.message
      span[:backtrace] = e.backtrace if e.backtrace
      # Always complete the span with end time
      span[:ended_at] = Time.current
      @spans << span
      raise e
    ensure
      # Always complete the span with end time
      span[:ended_at] = Time.current
      @spans << span unless @spans.include?(span)
    end

    # Re-raise any errors that were caught in test environments
    # This helps provide better context in test output
    if defined?(Rails) && Rails.env.test? && span[:error]
      Rails.logger.warn "Span '#{name}' captured an error: #{span[:error]}"
    end

    result
  end

  def clear
    @recorded_events = []
    @traces = []
    @spans = []
    @current_trace = nil
  end
end
