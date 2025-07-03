# frozen_string_literal: true

module BlogExamples
  module Post03
    module Concerns
      module ApiRequestHandling
        extend ActiveSupport::Concern

        included do
          # Initialize with mock service access
          def initialize(*args, **kwargs)
            # For blog examples, provide a dummy URL to satisfy Api::Config requirements
            # since we use mock services instead of real HTTP requests
            dummy_config = Tasker::StepHandler::Api::Config.new(url: 'http://localhost:3000')
            kwargs[:config] ||= dummy_config

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
        def handle_microservice_response(response, service_name)
          case response.status
          when 200..299
            # Success - return parsed body
            response.body
          when 400
            # Bad request - permanent failure, don't retry
            raise Tasker::PermanentError.new(
              "Bad request to #{service_name}: #{response.body}",
              error_code: 'BAD_REQUEST',
              context: { service: service_name, status: response.status }
            )
          when 401
            # Unauthorized - permanent failure, likely configuration issue
            raise Tasker::PermanentError.new(
              "Unauthorized request to #{service_name}. Check API credentials.",
              error_code: 'UNAUTHORIZED',
              context: { service: service_name }
            )
          when 403
            # Forbidden - permanent failure
            raise Tasker::PermanentError.new(
              "Forbidden request to #{service_name}: #{response.body}",
              error_code: 'FORBIDDEN',
              context: { service: service_name }
            )
          when 404
            # Not found - might be retryable if resource is being created
            nil # Let calling method decide what to do
          when 409
            # Conflict - resource already exists, typically idempotent success
            response.body
          when 422
            # Unprocessable entity - permanent failure, validation failed
            raise Tasker::PermanentError.new(
              "Validation failed in #{service_name}: #{response.body}",
              error_code: 'VALIDATION_ERROR',
              context: { service: service_name, validation_errors: response.body }
            )
          when 429
            # Rate limited - transient failure, use server-suggested delay
            retry_after = response.headers['retry-after']&.to_i || 60
            raise Tasker::RetryableError.new(
              "Rate limited by #{service_name}",
              retry_after: retry_after,
              context: { service: service_name, rate_limit_type: 'server_requested' }
            )
          when 500..599
            # Server error - transient failure, let Tasker's exponential backoff handle timing
            raise Tasker::RetryableError.new(
              "#{service_name} server error: #{response.status}",
              context: {
                service: service_name,
                status: response.status,
                error_type: 'server_error'
              }
            )
          else
            # Unexpected response - treat as permanent failure
            raise Tasker::PermanentError.new(
              "Unexpected response from #{service_name}: #{response.status}",
              error_code: 'UNEXPECTED_RESPONSE',
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
