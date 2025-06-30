# typed: false
# frozen_string_literal: true

module Tasker
  # Base class for all Tasker-specific errors that occur during workflow execution
  class ProceduralError < StandardError
  end

  # Error indicating a step failed but should be retried with backoff
  #
  # Use this error when an operation fails due to temporary conditions like:
  # - Network timeouts
  # - Rate limiting (429 status)
  # - Server errors (5xx status)
  # - Temporary service unavailability
  #
  # @example Basic retryable error
  #   raise Tasker::RetryableError, "Payment service timeout"
  #
  # @example With retry delay
  #   raise Tasker::RetryableError.new("Rate limited", retry_after: 60)
  #
  # @example With context for monitoring
  #   raise Tasker::RetryableError.new(
  #     "External API unavailable",
  #     retry_after: 30,
  #     context: { service: 'billing_api', error_code: 503 }
  #   )
  class RetryableError < ProceduralError
    # @return [Integer, nil] Suggested retry delay in seconds
    attr_reader :retry_after

    # @return [Hash] Additional context for error monitoring and debugging
    attr_reader :context

    # @param message [String] Error message
    # @param retry_after [Integer, nil] Suggested retry delay in seconds
    # @param context [Hash] Additional context for monitoring
    def initialize(message, retry_after: nil, context: {})
      super(message)
      @retry_after = retry_after
      @context = context
    end
  end

  # Error indicating a step failed permanently and should not be retried
  #
  # Use this error when an operation fails due to permanent conditions like:
  # - Invalid request data (400 status)
  # - Authentication/authorization failures (401/403 status)
  # - Validation errors (422 status)
  # - Resource not found when it should exist (404 status in some contexts)
  # - Business logic violations
  #
  # @example Basic permanent error
  #   raise Tasker::PermanentError, "Invalid user ID format"
  #
  # @example With error code for categorization
  #   raise Tasker::PermanentError.new(
  #     "Insufficient funds for transaction",
  #     error_code: 'INSUFFICIENT_FUNDS'
  #   )
  #
  # @example With context for monitoring
  #   raise Tasker::PermanentError.new(
  #     "User not authorized for this operation",
  #     error_code: 'AUTHORIZATION_FAILED',
  #     context: { user_id: 123, operation: 'admin_access' }
  #   )
  class PermanentError < ProceduralError
    # @return [String, nil] Machine-readable error code for categorization
    attr_reader :error_code

    # @return [Hash] Additional context for error monitoring and debugging
    attr_reader :context

    # @param message [String] Error message
    # @param error_code [String, nil] Machine-readable error code
    # @param context [Hash] Additional context for monitoring
    def initialize(message, error_code: nil, context: {})
      super(message)
      @error_code = error_code
      @context = context
    end
  end
end
