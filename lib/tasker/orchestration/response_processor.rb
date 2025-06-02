# frozen_string_literal: true

require_relative '../concerns/event_publisher'

module Tasker
  module Orchestration
    # ResponseProcessor handles API response validation and error detection
    #
    # This component provides focused responsibility for processing API responses,
    # determining if they indicate errors that require backoff handling,
    # and preparing context for error handling.
    class ResponseProcessor
      include Tasker::Concerns::EventPublisher

      # HTTP status codes that should trigger backoff behavior
      BACKOFF_ERROR_CODES = [429, 503].freeze

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

        # Check if this is a backoff-requiring error
        if BACKOFF_ERROR_CODES.include?(status)
          context = build_error_context(step, response, status)

          # Log the backoff error for observability
          Rails.logger.warn(
            "ResponseProcessor: API response requires backoff handling - " \
            "Status: #{status}, Step: #{step.name} (#{step.workflow_step_id})"
          )

          # Return context for backoff handling
          context
        else
          # Other error statuses don't require backoff but should still fail
          Rails.logger.error(
            "ResponseProcessor: API response indicates non-backoff error - " \
            "Status: #{status}, Step: #{step.name} (#{step.workflow_step_id})"
          )

          # Raise error for non-backoff failures
          body = extract_body(response)
          raise Faraday::Error, "API call failed with status #{status} and body #{body}"
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
            "expected Faraday::Response or Hash"
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
    end
  end
end
