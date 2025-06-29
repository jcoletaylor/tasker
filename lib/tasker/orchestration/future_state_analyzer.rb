# frozen_string_literal: true

module Tasker
  module Orchestration
    # Abstraction layer for analyzing Concurrent::Future states in our domain context
    #
    # This class encapsulates the complex state logic around Concurrent::Future objects,
    # providing domain-specific methods that express our actual intentions rather than
    # requiring callers to understand the intricacies of the Future state machine.
    #
    # The Concurrent::Future state machine has these states:
    # - unscheduled: Created but not yet executed
    # - pending: Scheduled but not yet started
    # - executing: Currently running
    # - fulfilled: Completed successfully
    # - rejected: Completed with error
    # - cancelled: Cancelled before completion
    #
    # Our domain needs are:
    # - Should we cancel this future? (pending futures)
    # - Should we wait for this future? (executing futures)
    # - Can we ignore this future? (completed or unscheduled futures)
    class FutureStateAnalyzer
      # Initialize with a Concurrent::Future object
      #
      # @param future [Concurrent::Future] The future to analyze
      def initialize(future)
        @future = future
      end

      # Should this future be cancelled during cleanup?
      #
      # We cancel futures that are pending (scheduled but not started).
      # This prevents them from starting when we're trying to clean up.
      #
      # @return [Boolean] true if the future should be cancelled
      def should_cancel?
        @future.pending?
      end

      # Should we wait for this future to complete during cleanup?
      #
      # We wait for futures that are actively executing to give them
      # a chance to complete gracefully before forcing cleanup.
      #
      # A future is "executing" if:
      # - It's incomplete (not finished)
      # - It's scheduled (not unscheduled)
      # - It's not pending (it has started)
      #
      # @return [Boolean] true if we should wait for this future
      def should_wait_for_completion?
        executing?
      end

      # Can we safely ignore this future during cleanup?
      #
      # We can ignore futures that are either:
      # - Already completed (fulfilled, rejected, or cancelled)
      # - Never scheduled (unscheduled)
      #
      # @return [Boolean] true if this future can be ignored
      def can_ignore?
        completed? || unscheduled?
      end

      # Is this future currently executing?
      #
      # A future is executing if it has been scheduled, started, but not completed.
      #
      # @return [Boolean] true if the future is actively executing
      def executing?
        @future.incomplete? && !@future.unscheduled? && !@future.pending?
      end

      # Is this future completed (in any completion state)?
      #
      # A future is completed if it's fulfilled, rejected, or cancelled.
      #
      # @return [Boolean] true if the future has completed
      def completed?
        @future.complete?
      end

      # Is this future unscheduled (never started)?
      #
      # An unscheduled future was created but never executed.
      #
      # @return [Boolean] true if the future is unscheduled
      delegate :unscheduled?, to: :@future

      # Is this future pending (scheduled but not started)?
      #
      # A pending future has been scheduled for execution but hasn't started yet.
      #
      # @return [Boolean] true if the future is pending
      delegate :pending?, to: :@future

      # Get a human-readable description of the future's state
      #
      # This is useful for logging and debugging.
      #
      # @return [String] A description of the current state
      def state_description
        return 'unscheduled' if unscheduled?
        return 'pending' if pending?
        return 'executing' if executing?
        return 'fulfilled' if @future.fulfilled?
        return 'rejected' if @future.rejected?
        return 'cancelled' if @future.cancelled?

        'unknown'
      end

      # Get detailed state information for debugging
      #
      # @return [Hash] Detailed state information
      def debug_state
        {
          state_description: state_description,
          should_cancel: should_cancel?,
          should_wait: should_wait_for_completion?,
          can_ignore: can_ignore?,
          raw_states: {
            pending: @future.pending?,
            complete: @future.complete?,
            incomplete: @future.incomplete?,
            unscheduled: @future.unscheduled?,
            fulfilled: @future.fulfilled?,
            rejected: @future.rejected?,
            cancelled: @future.cancelled?
          }
        }
      end
    end
  end
end
