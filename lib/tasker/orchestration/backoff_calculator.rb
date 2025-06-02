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

        # Apply reasonable cap for server-requested backoff
        max_server_backoff = 3600 # 1 hour maximum
        backoff_seconds = [backoff_seconds, max_server_backoff].min

        # Update step with backoff information
        step.backoff_request_seconds = backoff_seconds

        # Publish backoff event for observability
        publish_event(
          Tasker::Constants::ObservabilityEvents::Step::BACKOFF,
          {
            backoff_seconds: backoff_seconds,
            backoff_type: 'server_requested',
            retry_after: retry_after,
            step_id: step.workflow_step_id,
            step_name: step.name
          }
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
        step.attempts ||= 1

        backoff_seconds = calculate_exponential_delay(step)

        # Update step with backoff information
        step.backoff_request_seconds = backoff_seconds
        step.last_attempted_at = Time.zone.now

        # Publish backoff event for observability
        publish_exponential_backoff_event(step, backoff_seconds, context)

        Rails.logger.info(
          "BackoffCalculator: Applied exponential backoff of #{backoff_seconds} seconds " \
          "for step #{step.name} (#{step.workflow_step_id}), attempt #{step.attempts}"
        )
      end

      # Calculate exponential delay with jitter
      #
      # @param step [Tasker::WorkflowStep] The step with attempt information
      # @return [Float] Calculated backoff delay in seconds
      def calculate_exponential_delay(step)
        min_exponent = 2
        exponent = [step.attempts + 1, min_exponent].max
        base_delay = retry_delay || 1.0

        # Standard exponential backoff: base_delay * (2 ^ attempt)
        max_delay = 30.0 # Cap maximum delay at 30 seconds
        exponential_delay = [base_delay * (2**exponent), max_delay].min

        # Apply jitter to prevent thundering herd
        jitter_factor = jitter_factor_value
        retry_delay = exponential_delay * jitter_factor

        # Ensure minimum delay of at least half the base delay
        [retry_delay, base_delay * 0.5].max
      end

      # Publish exponential backoff event with detailed information
      #
      # @param step [Tasker::WorkflowStep] The step being backed off
      # @param backoff_seconds [Float] Calculated backoff delay
      # @param context [Hash] Response context
      def publish_exponential_backoff_event(step, backoff_seconds, _context)
        min_exponent = 2
        exponent = [step.attempts + 1, min_exponent].max

        publish_event(
          Tasker::Constants::ObservabilityEvents::Step::BACKOFF,
          {
            backoff_seconds: backoff_seconds,
            backoff_type: 'exponential',
            attempt: step.attempts,
            exponent: exponent,
            base_delay: retry_delay || 1.0,
            jitter_factor: jitter_factor_value,
            step_id: step.workflow_step_id,
            step_name: step.name
          }
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
        return 1.0 unless @config.respond_to?(:retry_delay)

        @config.retry_delay || 1.0
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
