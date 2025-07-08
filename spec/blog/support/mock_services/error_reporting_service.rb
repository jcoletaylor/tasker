# frozen_string_literal: true

require_relative 'base_mock_service'

# Mock Error Reporting Service (Sentry-like functionality)
# Simulates an error tracking and reporting service for observability testing
class MockErrorReportingService < BaseMockService
  # Custom exceptions
  class TimeoutError < StandardError; end
  class AuthenticationError < StandardError; end
  class RateLimitError < StandardError; end

  class << self
    # Track error reports
    def error_reports
      @error_reports ||= []
    end

    # Track breadcrumbs
    def breadcrumbs
      @breadcrumbs ||= []
    end

    # Track user context
    def user_contexts
      @user_contexts ||= []
    end

    def reset!
      super
      @error_reports = []
      @breadcrumbs = []
      @user_contexts = []
    end

    # Helper methods for test assertions
    def error_reported?(exception_class, message_pattern = nil)
      error_reports.any? do |report|
        class_match = report[:exception_class] == exception_class.to_s
        if message_pattern
          message_match = report[:message] =~ message_pattern
          class_match && message_match
        else
          class_match
        end
      end
    end

    def breadcrumb_added?(message_pattern)
      breadcrumbs.any? { |b| b[:message] =~ message_pattern }
    end

    def user_context_set?(user_id)
      user_contexts.any? { |ctx| ctx[:id] == user_id }
    end

    def latest_error_report
      error_reports.last
    end

    def error_count_for(exception_class)
      error_reports.count { |report| report[:exception_class] == exception_class.to_s }
    end
  end

  # Report an exception
  # @param exception [Exception] The exception to report
  # @param context [Hash] Additional context data
  # @param tags [Hash] Tags for categorization
  # @param level [String] Error level (error, warning, info, debug)
  def capture_exception(exception, context: {}, tags: {}, level: 'error')
    log_call(:capture_exception, {
      exception_class: exception.class.name,
      message: exception.message,
      context: context,
      tags: tags,
      level: level
    })
    
    error_report = {
      exception_class: exception.class.name,
      message: exception.message,
      backtrace: exception.backtrace&.first(10) || [],
      context: context,
      tags: tags,
      level: level,
      timestamp: Time.current,
      event_id: generate_id('error'),
      fingerprint: generate_fingerprint(exception),
      user: current_user_context,
      breadcrumbs: current_breadcrumbs.dup
    }
    
    self.class.error_reports << error_report
    
    handle_response(:capture_exception, {
      status: 'ok',
      event_id: error_report[:event_id]
    })
  end

  # Report a message (not an exception)
  # @param message [String] The message to report
  # @param context [Hash] Additional context data
  # @param tags [Hash] Tags for categorization
  # @param level [String] Message level (error, warning, info, debug)
  def capture_message(message, context: {}, tags: {}, level: 'info')
    log_call(:capture_message, {
      message: message,
      context: context,
      tags: tags,
      level: level
    })
    
    message_report = {
      exception_class: nil,
      message: message,
      backtrace: caller(1, 10),
      context: context,
      tags: tags,
      level: level,
      timestamp: Time.current,
      event_id: generate_id('message'),
      fingerprint: generate_message_fingerprint(message),
      user: current_user_context,
      breadcrumbs: current_breadcrumbs.dup
    }
    
    self.class.error_reports << message_report
    
    handle_response(:capture_message, {
      status: 'ok',
      event_id: message_report[:event_id]
    })
  end

  # Add a breadcrumb
  # @param message [String] Breadcrumb message
  # @param category [String] Breadcrumb category
  # @param level [String] Breadcrumb level
  # @param data [Hash] Additional breadcrumb data
  def add_breadcrumb(message, category: 'default', level: 'info', data: {})
    log_call(:add_breadcrumb, {
      message: message,
      category: category,
      level: level,
      data: data
    })
    
    breadcrumb = {
      message: message,
      category: category,
      level: level,
      data: data,
      timestamp: Time.current
    }
    
    self.class.breadcrumbs << breadcrumb
    
    # Keep only the last 50 breadcrumbs
    self.class.breadcrumbs.shift if self.class.breadcrumbs.length > 50
    
    handle_response(:add_breadcrumb, { status: 'ok' })
  end

  # Set user context
  # @param user_data [Hash] User identification and context
  def set_user_context(user_data)
    log_call(:set_user_context, { user_data: user_data })
    
    user_context = {
      id: user_data[:id],
      email: user_data[:email],
      name: user_data[:name],
      ip_address: user_data[:ip_address],
      additional_data: user_data.except(:id, :email, :name, :ip_address),
      timestamp: Time.current
    }
    
    self.class.user_contexts << user_context
    @current_user_context = user_context
    
    handle_response(:set_user_context, { status: 'ok' })
  end

  # Set tags context
  # @param tags [Hash] Tags to set
  def set_tags(tags)
    log_call(:set_tags, { tags: tags })
    
    @current_tags = (@current_tags || {}).merge(tags)
    
    handle_response(:set_tags, { status: 'ok' })
  end

  # Set extra context
  # @param context [Hash] Extra context data
  def set_extra_context(context)
    log_call(:set_extra_context, { context: context })
    
    @current_extra_context = (@current_extra_context || {}).merge(context)
    
    handle_response(:set_extra_context, { status: 'ok' })
  end

  # Record a performance transaction
  # @param name [String] Transaction name
  # @param operation [String] Operation type
  # @param data [Hash] Transaction data
  def start_transaction(name, operation: 'default', data: {})
    log_call(:start_transaction, {
      name: name,
      operation: operation,
      data: data
    })
    
    transaction = {
      name: name,
      operation: operation,
      data: data,
      start_time: Time.current,
      transaction_id: generate_id('transaction')
    }
    
    @current_transaction = transaction
    
    handle_response(:start_transaction, {
      status: 'ok',
      transaction_id: transaction[:transaction_id]
    })
  end

  # Finish a performance transaction
  # @param status [String] Transaction status
  def finish_transaction(status: 'ok')
    return unless @current_transaction
    
    log_call(:finish_transaction, { status: status })
    
    @current_transaction[:end_time] = Time.current
    @current_transaction[:duration] = @current_transaction[:end_time] - @current_transaction[:start_time]
    @current_transaction[:status] = status
    
    # In a real implementation, this would be sent to the error reporting service
    
    result = @current_transaction.dup
    @current_transaction = nil
    
    handle_response(:finish_transaction, {
      status: 'ok',
      duration: result[:duration]
    })
  end

  # Health check for error reporting service
  def health_check
    log_call(:health_check)
    
    handle_response(:health_check, {
      status: 'healthy',
      version: '7.4.0',
      uptime: '24h',
      errors_processed: self.class.error_reports.length
    })
  end

  private

  def current_user_context
    @current_user_context
  end

  def current_breadcrumbs
    self.class.breadcrumbs
  end

  def generate_fingerprint(exception)
    # Simple fingerprint based on exception class and message
    Digest::MD5.hexdigest("#{exception.class.name}:#{exception.message}")
  end

  def generate_message_fingerprint(message)
    # Simple fingerprint based on message
    Digest::MD5.hexdigest(message)
  end
end

# Global error reporting instance for easy access in tests
# This simulates having a global error reporter like Sentry
module Tasker
  def self.error_reporter
    @error_reporter ||= MockErrorReportingService.new
  end

  def self.reset_error_reporter!
    @error_reporter = MockErrorReportingService.new
    MockErrorReportingService.reset!
  end
end