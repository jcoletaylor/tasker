# frozen_string_literal: true

require_relative '../concerns/event_publisher'
require_relative '../errors'

module Tasker
  module Orchestration
    # ResponseProcessor handles API response validation and error detection
    #
    # This component provides focused responsibility for processing API responses,
    # determining if they indicate errors that require backoff handling,
    # and preparing context for error handling.
    class ResponseProcessor
      include Tasker::Concerns::EventPublisher

      # HTTP status codes that should trigger backoff behavior (temporary failures)
      BACKOFF_ERROR_CODES = [429, 503].freeze

      # HTTP status codes that indicate permanent failures (don't retry)
      PERMANENT_ERROR_CODES = [400, 401, 403, 404, 422].freeze

      # HTTP status codes that indicate a successful request
      SUCCESS_CODES = (200..226)

      # Process an API response and determine if it requires error handling
      #
      # @param step [Tasker::WorkflowStep] The current step being processed
      # @param response [Faraday::Response, Hash] The API response to process
      # @return [Hash, nil] Context for error handling if response indicates error, nil if successful
      # @raise [Faraday::Error] If response indicates a backoff-requiring error
      def process_response(step, response)
        status = extract_status(response)

        # Successful responses don't need special handling
        return nil if SUCCESS_CODES.include?(status)

        # Categorize error type and raise appropriate Tasker error
        if BACKOFF_ERROR_CODES.include?(status)
          # Temporary failures that should be retried with backoff
          context = build_error_context(step, response, status)
          retry_after = extract_retry_after(response)

          Rails.logger.warn(
            'ResponseProcessor: API response requires backoff handling - ' \
            "Status: #{status}, Step: #{step.name} (#{step.workflow_step_id})"
          )

          # Parse retry_after immediately to avoid timing issues with date formats
          parsed_retry_after = if retry_after&.match?(/^\d+$/)
                                 retry_after.to_i
                               elsif retry_after
                                 # Parse HTTP date format immediately
                                 retry_time = Time.zone.parse(retry_after)
                                 [(retry_time - Time.zone.now).to_i, 1].max
                               end

          raise Tasker::RetryableError.new(
            "API call failed with retryable status #{status}",
            retry_after: parsed_retry_after,
            context: context
          )
        elsif PERMANENT_ERROR_CODES.include?(status)
          # Permanent failures that should not be retried
          body = extract_body(response)
          context = build_error_context(step, response, status)

          Rails.logger.error(
            'ResponseProcessor: API response indicates permanent error - ' \
            "Status: #{status}, Step: #{step.name} (#{step.workflow_step_id})"
          )

          raise Tasker::PermanentError.new(
            "API call failed with permanent status #{status}: #{body}",
            error_code: "HTTP_#{status}",
            context: context
          )
        else
          # Other server errors (5xx) - treat as retryable but without forced backoff
          body = extract_body(response)
          context = build_error_context(step, response, status)

          Rails.logger.error(
            'ResponseProcessor: API response indicates server error - ' \
            "Status: #{status}, Step: #{step.name} (#{step.workflow_step_id})"
          )

          # Create a special RetryableError that doesn't apply backoff
          error = Tasker::RetryableError.new(
            "API call failed with server error #{status}: #{body}",
            context: context
          )

          # Mark this error as not requiring backoff
          error.define_singleton_method(:skip_backoff?) { true }

          raise error
        end
      end

      private

      # Extract status code from response (handles both Faraday::Response and Hash)
      #
      # @param response [Faraday::Response, Hash] The response object
      # @return [Integer] The HTTP status code
      def extract_status(response)
        if response.is_a?(Hash)
          response[:status]
        elsif response.respond_to?(:status)
          response.status
        else
          # Fallback - log and raise error for unexpected response types
          Rails.logger.error(
            "ResponseProcessor: Unexpected response type #{response.class}, " \
            'expected Faraday::Response or Hash'
          )
          raise ArgumentError, "Cannot extract status from response of type #{response.class}"
        end
      end

      # Extract response body for error reporting
      #
      # @param response [Faraday::Response, Hash] The response object
      # @return [String] The response body
      def extract_body(response)
        response.is_a?(Hash) ? response[:body] : response.body
      end

      # Build error context for backoff handling
      #
      # @param step [Tasker::WorkflowStep] The current step
      # @param response [Faraday::Response, Hash] The response object
      # @param status [Integer] The HTTP status code
      # @return [Hash] Context information for error handling
      def build_error_context(step, response, status)
        {
          step_id: step.workflow_step_id,
          step_name: step.name,
          status: status,
          response: response,
          headers: extract_headers(response)
        }
      end

      # Extract headers from response (handles both Faraday::Response and Hash)
      #
      # @param response [Faraday::Response, Hash] The response object
      # @return [Hash] The response headers
      def extract_headers(response)
        response.is_a?(Hash) ? response[:headers] || {} : response.headers
      end

      # Extract retry-after header value for rate limiting
      #
      # @param response [Faraday::Response, Hash] The response object
      # @return [String, nil] Retry delay as string (for parsing), nil if not present
      def extract_retry_after(response)
        headers = extract_headers(response)
        headers['retry-after'] || headers['Retry-After']
      end
    end
  end
end
