module CircuitBreakerPattern
  extend ActiveSupport::Concern

  class CircuitBreakerError < StandardError; end
  class CircuitOpenError < CircuitBreakerError; end

  included do
    class_attribute :circuit_breakers
    self.circuit_breakers = {}
  end

  # Main circuit breaker wrapper
  def with_circuit_breaker(service_name, &block)
    breaker = circuit_breaker_for(service_name)
    
    case breaker.state
    when :open
      # Fire event for monitoring
      publish_event('circuit_breaker_opened', {
        service: service_name,
        failure_count: breaker.failure_count,
        last_failure_at: breaker.last_failure_at,
        will_retry_at: breaker.next_attempt_at
      })
      
      raise CircuitOpenError, "Circuit breaker is OPEN for #{service_name}. Service has failed #{breaker.failure_count} times. Will retry at #{breaker.next_attempt_at}"
      
    when :half_open
      # Try one request to see if service recovered
      execute_with_monitoring(service_name, breaker, &block)
      
    when :closed
      # Normal operation
      execute_with_monitoring(service_name, breaker, &block)
    end
  end

  private

  def execute_with_monitoring(service_name, breaker, &block)
    start_time = Time.current
    
    begin
      # Fire start event
      publish_event('service_call_started', {
        service: service_name,
        breaker_state: breaker.state,
        correlation_id: task.annotations['correlation_id']
      })
      
      result = yield
      
      # Record success
      breaker.record_success
      duration_ms = ((Time.current - start_time) * 1000).to_i
      
      # Fire success event
      publish_event('service_call_completed', {
        service: service_name,
        duration_ms: duration_ms,
        breaker_state: breaker.state,
        correlation_id: task.annotations['correlation_id']
      })
      
      # Close circuit if we've had enough successes
      if breaker.state == :half_open && breaker.success_count >= breaker.success_threshold
        breaker.close!
        publish_event('circuit_breaker_closed', {
          service: service_name,
          success_count: breaker.success_count
        })
      end
      
      result
      
    rescue => error
      # Record failure
      breaker.record_failure
      duration_ms = ((Time.current - start_time) * 1000).to_i
      
      # Fire failure event
      publish_event('service_call_failed', {
        service: service_name,
        error_class: error.class.name,
        error_message: error.message,
        duration_ms: duration_ms,
        breaker_state: breaker.state,
        failure_count: breaker.failure_count,
        correlation_id: task.annotations['correlation_id']
      })
      
      raise
    end
  end

  def circuit_breaker_for(service_name)
    self.class.circuit_breakers[service_name] ||= CircuitBreaker.new(
      service_name: service_name,
      failure_threshold: circuit_breaker_config[service_name][:failure_threshold] || 5,
      recovery_timeout: circuit_breaker_config[service_name][:recovery_timeout] || 60,
      success_threshold: circuit_breaker_config[service_name][:success_threshold] || 2
    )
  end

  def circuit_breaker_config
    @circuit_breaker_config ||= {
      'user_service' => {
        failure_threshold: 5,
        recovery_timeout: 60,
        success_threshold: 2
      },
      'billing_service' => {
        failure_threshold: 3,      # More sensitive - money involved
        recovery_timeout: 120,     # Longer recovery time
        success_threshold: 3       # Need more successes to trust again
      },
      'preferences_service' => {
        failure_threshold: 10,     # Less critical - can fail more
        recovery_timeout: 30,      # Quick recovery
        success_threshold: 1       # One success is enough
      },
      'notification_service' => {
        failure_threshold: 20,     # Very tolerant - emails can retry
        recovery_timeout: 30,
        success_threshold: 1
      }
    }.with_indifferent_access
  end

  # Simple circuit breaker implementation
  class CircuitBreaker
    attr_reader :service_name, :failure_threshold, :recovery_timeout, :success_threshold
    attr_reader :failure_count, :success_count, :last_failure_at, :state

    def initialize(service_name:, failure_threshold: 5, recovery_timeout: 60, success_threshold: 2)
      @service_name = service_name
      @failure_threshold = failure_threshold
      @recovery_timeout = recovery_timeout
      @success_threshold = success_threshold
      @failure_count = 0
      @success_count = 0
      @last_failure_at = nil
      @state = :closed
    end

    def record_failure
      @failure_count += 1
      @success_count = 0
      @last_failure_at = Time.current
      
      if @failure_count >= @failure_threshold
        @state = :open
      end
    end

    def record_success
      @success_count += 1
      
      if @state == :half_open && @success_count >= @success_threshold
        close!
      end
    end

    def close!
      @state = :closed
      @failure_count = 0
      @success_count = 0
      @last_failure_at = nil
    end

    def state
      if @state == :open && Time.current >= next_attempt_at
        @state = :half_open
        @success_count = 0
      end
      
      @state
    end

    def next_attempt_at
      return nil unless @last_failure_at
      @last_failure_at + @recovery_timeout.seconds
    end
  end
end