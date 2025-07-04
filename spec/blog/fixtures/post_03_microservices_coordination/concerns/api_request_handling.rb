# frozen_string_literal: true

# API Request Handling for Microservices Coordination
#
# This concern demonstrates how to handle API requests in a microservices architecture
# using Tasker's built-in circuit breaker functionality through proper error classification.
#
# KEY INSIGHT: Tasker provides superior circuit breaker functionality through its
# SQL-driven retry architecture. Custom circuit breaker patterns are unnecessary and
# actually work against Tasker's distributed coordination capabilities.
#
module BlogExamples
  module Post03
    module Concerns
      module ApiRequestHandling
        extend ActiveSupport::Concern

        included do
          # Initialize with mock service access for blog examples
          def initialize(*args, **kwargs)
            # Handle config properly - if we get a hash from handler_config, convert it to a proper Config object
            if kwargs[:config].is_a?(Hash)
              config_hash = kwargs[:config]
              kwargs[:config] = Tasker::StepHandler::Api::Config.new(
                url: config_hash['url'] || config_hash[:url] || 'http://localhost:3000'
              )
            elsif kwargs[:config].nil?
              # For blog examples, provide a dummy URL to satisfy Api::Config requirements
              # since we use mock services instead of real HTTP requests
              kwargs[:config] = Tasker::StepHandler::Api::Config.new(url: 'http://localhost:3000')
            end

            super
            @mock_services = {
              user_service: BlogExamples::MockServices::MockUserService.new,
              billing_service: BlogExamples::MockServices::MockBillingService.new,
              preferences_service: BlogExamples::MockServices::MockPreferencesService.new,
              notification_service: BlogExamples::MockServices::MockNotificationService.new
            }
          end
        end

        protected

        # Get mock service by name (business logic, not framework)
        def get_service(service_name)
          @mock_services[service_name.to_sym] || raise("Unknown service: #{service_name}")
        end

        # Enhanced response handler leveraging Tasker's error classification
        # This is where Tasker's circuit breaker logic is implemented - through error types!
        def handle_microservice_response(response, service_name)
          case response.status
          when 200..299
            # Success - circuit breaker records success automatically
            response.body

          when 400, 422
            # Client errors - PERMANENT failures
            # Tasker's circuit breaker will NOT retry these (circuit stays "open" indefinitely)
            raise Tasker::PermanentError.new(
              "#{service_name} validation error: #{response.body}",
              error_code: 'CLIENT_VALIDATION_ERROR',
              context: { service: service_name, status: response.status }
            )

          when 401, 403
            # Authentication/authorization errors - PERMANENT failures
            raise Tasker::PermanentError.new(
              "#{service_name} authentication failed: #{response.status}",
              error_code: 'AUTH_ERROR',
              context: { service: service_name }
            )

          when 404
            # Not found - usually PERMANENT, but depends on context
            raise Tasker::PermanentError.new(
              "#{service_name} resource not found",
              error_code: 'RESOURCE_NOT_FOUND',
              context: { service: service_name }
            )

          when 409
            # Conflict - resource already exists, typically idempotent success
            response.body

          when 429
            # Rate limiting - RETRYABLE with server-specified backoff
            # This is where Tasker's intelligent backoff shines!
            retry_after = response.headers['retry-after']&.to_i || 60
            raise Tasker::RetryableError.new(
              "#{service_name} rate limited",
              retry_after: retry_after,
              context: { service: service_name, rate_limit_type: 'server_requested' }
            )

          when 500..599
            # Server errors - RETRYABLE with exponential backoff
            # Tasker's circuit breaker will handle intelligent retry timing
            raise Tasker::RetryableError.new(
              "#{service_name} server error: #{response.status}",
              context: {
                service: service_name,
                status: response.status,
                error_type: 'server_error'
              }
            )

          else
            # Unknown status codes - treat as retryable to be safe
            raise Tasker::RetryableError.new(
              "#{service_name} unknown error: #{response.status}",
              context: { service: service_name, status: response.status }
            )
          end
        end

        # Correlation ID generation for distributed tracing
        def correlation_id
          @correlation_id ||= @current_task&.context&.dig('correlation_id') || generate_correlation_id
        end

        def generate_correlation_id
          "reg_#{Time.current.to_i}_#{SecureRandom.hex(4)}"
        end

        # Business logic helper methods
        def step_results(sequence, step_name)
          step = sequence.steps.find { |s| s.name == step_name }
          step&.results || {}
        end

        def log_api_call(method, url, options = {})
          log_structured(:info, 'API call initiated', {
                           method: method.to_s.upcase,
                           url: url,
                           service: extract_service_name(url),
                           timeout: options[:timeout]
                         })
        end

        def log_api_response(method, url, response, duration_ms)
          status = response.respond_to?(:status) ? response.status : response.code

          # Handle response body - convert to JSON string if it's a Hash
          body = response.respond_to?(:body) ? response.body : response.body
          body_size = if body.is_a?(Hash)
                        body.to_json.bytesize
                      elsif body.respond_to?(:bytesize)
                        body.bytesize
                      else
                        body.to_s.bytesize
                      end

          log_structured(:info, 'API call completed', {
                           method: method.to_s.upcase,
                           url: url,
                           service: extract_service_name(url),
                           status_code: status,
                           duration_ms: duration_ms,
                           response_size: body_size
                         })
        end

        def log_structured(level, message, context = {})
          full_context = {
            message: message,
            correlation_id: correlation_id,
            step_name: @current_step&.name,
            task_id: @current_task&.id,
            timestamp: Time.current.iso8601
          }.merge(context)

          puts "[#{level.upcase}] #{full_context.to_json}" if Rails.env.test?
        end

        def extract_service_name(url)
          uri = URI.parse(url)
          # Extract service name from hostname or path
          if uri.hostname&.include?('localhost')
            # Local development - extract from port or path
            case uri.port
            when 3001
              'user_service'
            when 3002
              'billing_service'
            when 3003
              'preferences_service'
            when 3004
              'notification_service'
            else
              uri.path.split('/')[1] || 'unknown_service'
            end
          else
            # Production - extract from subdomain or hostname
            uri.hostname&.split('.')&.first || 'unknown_service'
          end
        end

        # Convenience methods for step handlers to set context
        def set_current_context(task, step, sequence = nil)
          @current_task = task
          @current_step = step
          @current_sequence = sequence
        end
      end
    end
  end
end

# WHY NO CUSTOM CIRCUIT BREAKER?
#
# Tasker's architecture already implements sophisticated circuit breaker patterns:
#
# 1. **Fail-Fast**: Through error classification (PermanentError vs RetryableError)
# 2. **Intelligent Backoff**: SQL-driven exponential backoff with jitter
# 3. **Automatic Recovery**: Steps become retry_eligible when backoff expires
# 4. **Distributed Coordination**: Multiple workers coordinate through database state
# 5. **Persistent State**: Circuit state survives process restarts and deployments
# 6. **Rich Observability**: SQL queries show circuit health across all services
#
# Custom circuit breaker patterns would:
# - Duplicate functionality already provided by the framework
# - Create coordination issues between in-memory and database state
# - Reduce observability (harder to query circuit state)
# - Add unnecessary complexity and potential bugs
#
# The key insight: **Persistence + distributed coordination > in-memory circuit objects**
# for workflow orchestration systems.
