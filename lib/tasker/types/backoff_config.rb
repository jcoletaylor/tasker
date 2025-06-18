# frozen_string_literal: true

module Tasker
  module Types
    # Configuration type for retry backoff calculation settings
    #
    # This configuration exposes previously hardcoded backoff timing constants
    # used in retry logic and exponential backoff calculations.
    #
    # @example Basic usage
    #   config = BackoffConfig.new(
    #     max_backoff_seconds: 120
    #   )
    #
    # @example With custom backoff progression
    #   config = BackoffConfig.new(
    #     default_backoff_seconds: [1, 2, 5, 10, 20, 60],
    #     max_backoff_seconds: 300,
    #     backoff_multiplier: 2.5,
    #     jitter_enabled: true,
    #     jitter_max_percentage: 0.15
    #   )
    class BackoffConfig < BaseConfig
      transform_keys(&:to_sym)

      # Default backoff progression in seconds
      #
      # This array defines the backoff progression for retries.
      # Each element represents the backoff time for that attempt number.
      # If more attempts are made than elements in this array,
      # the exponential backoff calculation takes over.
      #
      # @!attribute [r] default_backoff_seconds
      #   @return [Array<Integer>] Backoff progression in seconds
      attribute :default_backoff_seconds, Types::Array.of(Types::Integer)
                                                      .default([1, 2, 4, 8, 16, 32].freeze)

      # Maximum backoff time in seconds
      #
      # This value caps the exponential backoff calculation to prevent
      # excessively long delays between retry attempts.
      #
      # @!attribute [r] max_backoff_seconds
      #   @return [Integer] Maximum backoff time in seconds
      attribute :max_backoff_seconds, Types::Integer.default(300)

      # Multiplier for exponential backoff calculation
      #
      # This value is used in the exponential backoff formula:
      # backoff_time = attempt_number ^ backoff_multiplier * base_seconds
      #
      # @!attribute [r] backoff_multiplier
      #   @return [Float] Exponential backoff multiplier
      attribute :backoff_multiplier, Types::Float.default(2.0)

      # Whether to apply jitter to backoff calculations
      #
      # Jitter helps prevent the "thundering herd" problem where
      # many failed steps retry at exactly the same time.
      #
      # @!attribute [r] jitter_enabled
      #   @return [Boolean] Whether jitter is enabled
      attribute :jitter_enabled, Types::Bool.default(true)

      # Maximum jitter percentage
      #
      # When jitter is enabled, the actual backoff time will be
      # randomly adjusted by up to this percentage.
      # E.g., 0.1 means ±10% variation.
      #
      # @!attribute [r] jitter_max_percentage
      #   @return [Float] Maximum jitter as a decimal percentage
      attribute :jitter_max_percentage, Types::Float.default(0.1)

      # Calculate backoff time for a given attempt
      #
      # @param attempt_number [Integer] The retry attempt number (1-based)
      # @return [Integer] Backoff time in seconds
      def calculate_backoff_seconds(attempt_number)
        return 0 if attempt_number <= 0

        # Use predefined progression if available
        base_backoff = if attempt_number <= default_backoff_seconds.length
                         default_backoff_seconds[attempt_number - 1]
                       else
                         # Use exponential backoff for attempts beyond predefined progression
                         (attempt_number**backoff_multiplier).to_i
                       end

        # Apply maximum limit
        backoff_time = [base_backoff, max_backoff_seconds].min

        # Apply jitter if enabled
        if jitter_enabled
          jitter_range = (backoff_time * jitter_max_percentage).round
          jitter = Random.rand(-jitter_range..jitter_range)
          backoff_time = [backoff_time + jitter, 1].max # Ensure minimum 1 second
        end

        backoff_time
      end
    end
  end
end
