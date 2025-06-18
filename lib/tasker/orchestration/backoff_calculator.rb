# frozen_string_literal: true

require_relative '../concerns/event_publisher'
require_relative 'retry_header_parser'

module Tasker
  module Orchestration
    # BackoffCalculator handles all backoff logic for API retries
    #
    # This component provides unified handling of both server-requested backoff
    # (via Retry-After headers) and exponential backoff calculations.
    # It publishes appropriate events for observability.
    class BackoffCalculator
      include Tasker::Concerns::EventPublisher

      # Initialize the backoff calculator
      #
      # @param config [Object] Configuration object with backoff settings
      # @param retry_parser [RetryHeaderParser] Parser for Retry-After headers (injectable for testing)
      def initialize(config: nil, retry_parser: RetryHeaderParser.new)
        @config = config
        @retry_parser = retry_parser
      end

      # Calculate and apply backoff for a step based on response context
      #
      # This method determines whether to use server-requested backoff or
      # exponential backoff, calculates the appropriate delay, and updates
      # the step with backoff information.
      #
      # @param step [Tasker::WorkflowStep] The step requiring backoff
      # @param context [Hash] Response context containing headers and metadata
      def calculate_and_apply_backoff(step, context)
        retry_after = extract_retry_after_header(context)

        if retry_after.present?
          apply_server_requested_backoff(step, retry_after)
        elsif backoff_enabled?
          apply_exponential_backoff(step, context)
        else
          Rails.logger.warn(
            "BackoffCalculator: No backoff strategy available for step #{step.name} (#{step.workflow_step_id})"
          )
        end
      end

      private

      # Get backoff configuration with memoization
      #
      # @return [Tasker::Types::BackoffConfig] The backoff configuration
      def backoff_config
        @backoff_config ||= Tasker.configuration.backoff
      end

      # Extract Retry-After header from response context
      #
      # @param context [Hash] Response context
      # @return [String, nil] Retry-After header value if present
      def extract_retry_after_header(context)
        headers = context[:headers] || {}
        headers['Retry-After'] || headers['retry-after']
      end

      # Apply server-requested backoff using Retry-After header
      #
      # @param step [Tasker::WorkflowStep] The step to apply backoff to
      # @param retry_after [String] The Retry-After header value
      def apply_server_requested_backoff(step, retry_after)
        backoff_seconds = @retry_parser.parse_retry_after(retry_after)

        # Apply configurable cap for server-requested backoff
        max_server_backoff = backoff_config.max_backoff_seconds
        backoff_seconds = [backoff_seconds, max_server_backoff].min

        # Update step with backoff information
        step.backoff_request_seconds = backoff_seconds

        # Publish backoff event for observability
        publish_step_backoff(
          step,
          backoff_seconds: backoff_seconds,
          backoff_type: 'server_requested',
          retry_after: retry_after
        )

        Rails.logger.info(
          "BackoffCalculator: Applied server-requested backoff of #{backoff_seconds} seconds " \
          "for step #{step.name} (#{step.workflow_step_id})"
        )
      end

      # Apply exponential backoff calculation
      #
      # @param step [Tasker::WorkflowStep] The step to apply backoff to
      # @param context [Hash] Response context for event publishing
      def apply_exponential_backoff(step, context)
        # Ensure attempts is properly initialized
        step.attempts ||= 0

        # Convert 0-based attempts to 1-based for backoff calculation
        # (step.attempts = 0 means first attempt, should get backoff[0])
        attempt_for_calculation = step.attempts + 1
        backoff_seconds = calculate_exponential_delay(attempt_for_calculation)

        # Update step with backoff information
        step.backoff_request_seconds = backoff_seconds
        step.last_attempted_at = Time.zone.now

        # Publish backoff event for observability
        publish_exponential_backoff_event(step, backoff_seconds, context, attempt_for_calculation)

        Rails.logger.info(
          "BackoffCalculator: Applied exponential backoff of #{backoff_seconds} seconds " \
          "for step #{step.name} (#{step.workflow_step_id}), attempt #{step.attempts}"
        )
      end

      # Calculate exponential delay with jitter
      #
      # @param attempt_number [Integer] The 1-based attempt number
      # @return [Float] Calculated backoff delay in seconds
      def calculate_exponential_delay(attempt_number)
        # Use BackoffConfig's calculate_backoff_seconds method
        backoff_seconds = backoff_config.calculate_backoff_seconds(attempt_number)

        # Ensure minimum delay of at least half the first backoff value
        min_delay = backoff_config.default_backoff_seconds.first * 0.5
        [backoff_seconds, min_delay].max
      end

      # Publish exponential backoff event with detailed information
      #
      # @param step [Tasker::WorkflowStep] The step being backed off
      # @param backoff_seconds [Float] Calculated backoff delay
      # @param context [Hash] Response context
      # @param attempt_number [Integer] The 1-based attempt number
      def publish_exponential_backoff_event(step, backoff_seconds, _context, attempt_number)
        publish_step_backoff(
          step,
          backoff_seconds: backoff_seconds,
          backoff_type: 'exponential',
          attempt: step.attempts,
          calculated_attempt: attempt_number,
          base_delay: backoff_config.default_backoff_seconds.first,
          multiplier: backoff_config.backoff_multiplier,
          jitter_enabled: backoff_config.jitter_enabled,
          jitter_max_percentage: backoff_config.jitter_max_percentage
        )
      end

      # Check if exponential backoff is enabled
      #
      # @return [Boolean] True if exponential backoff should be used
      def backoff_enabled?
        return true unless @config # Default to enabled if no config

        if @config.respond_to?(:enable_exponential_backoff)
          @config.enable_exponential_backoff
        else
          true
        end
      end

      # Get retry delay from configuration
      #
      # @return [Float] Base retry delay in seconds
      def retry_delay
        return backoff_config.default_backoff_seconds.first.to_f unless @config.respond_to?(:retry_delay)

        @config.retry_delay || backoff_config.default_backoff_seconds.first.to_f
      end

      # Get jitter factor from configuration
      #
      # @return [Float] Jitter factor for randomness (0.0-1.0)
      def jitter_factor_value
        return rand unless @config.respond_to?(:jitter_factor)

        @config.jitter_factor || rand
      end
    end
  end
end
