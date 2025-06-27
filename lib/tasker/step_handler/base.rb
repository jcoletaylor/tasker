# frozen_string_literal: true

require_relative '../concerns/event_publisher'
require_relative '../concerns/structured_logging'

module Tasker
  module StepHandler
    # Automatic event publishing wrapper for step handlers
    #
    # This module automatically publishes step lifecycle events around
    # the execution of step handler methods, eliminating the need for
    # developers to manually add event publishing code in their handlers.
    #
    # Uses Ruby's prepend mechanism to wrap the handle method transparently.
    module AutomaticEventPublishing
      # Automatically publish events around step handler execution
      #
      # This method wraps the original handle method and ensures that
      # appropriate lifecycle events are published without requiring
      # developers to add event publishing code manually.
      #
      # ⚠️  IMPORTANT: This method should NEVER be overridden by developers.
      # Developers should implement the process() method instead.
      #
      # @param task [Tasker::Task] The task being executed
      # @param sequence [Tasker::Types::StepSequence] The sequence of steps
      # @param step [Tasker::WorkflowStep] The current step being handled
      # @return [Object] The result of processing the step
      def handle(task, sequence, step)
        # Publish step started event automatically
        publish_step_started(step)

        # Fire the before_handle event for compatibility with existing code
        publish_step_before_handle(step)

        begin
          # Call the original handle method implemented by the framework
          result = super

          # Publish step completed event automatically
          publish_step_completed(step)

          result
        rescue StandardError => e
          # Publish step failed event automatically with error information
          publish_step_failed(step, error: e)

          # Re-raise the exception to preserve error handling behavior
          raise
        end
      end
    end

    # Base class for all step handlers that defines the common interface
    # and provides lifecycle event handling
    #
    # ⚠️  IMPORTANT DEVELOPER GUIDANCE:
    # - NEVER override the handle() method - it's framework-only code
    # - ALWAYS implement the process() method - that's your extension point
    # - The handle() method automatically publishes lifecycle events and calls your process() method
    #
    # 📊  STRUCTURED LOGGING AVAILABLE:
    # All step handlers automatically include structured logging capabilities:
    # - Use log_structured() to emit structured logs with correlation IDs
    # - Correlation ID is automatically extracted from the task for traceability
    # - Example: log_structured(level: :info, message: "Processing order", order_id: order.id)
    class Base
      # Use prepend to automatically wrap handle methods with event publishing
      prepend AutomaticEventPublishing
      include Tasker::Concerns::EventPublisher
      include Tasker::Concerns::StructuredLogging

      # Creates a new step handler instance
      #
      # @param config [Object, nil] Optional configuration for the handler
      # @return [Base] A new step handler instance
      def initialize(config: nil)
        @config = config
      end

      # Framework method that coordinates step execution with automatic event publishing
      #
      # ⚠️  NEVER OVERRIDE THIS METHOD IN SUBCLASSES
      # This method is framework-only code that:
      # 1. Is automatically wrapped with event publishing via AutomaticEventPublishing
      # 2. Calls the developer-implemented process() method
      # 3. Handles framework-level concerns like logging and error propagation
      #
      # @param task [Tasker::Task] The task being executed
      # @param sequence [Tasker::Types::StepSequence] The sequence of steps
      # @param step [Tasker::WorkflowStep] The current step being handled
      # @return [Object] The result of processing the step
      def handle(task, sequence, step)
        log_structured(
          :debug,
          "Starting step execution",
          step_id: step.workflow_step_id,
          step_name: step.name,
          correlation_id: task.task_id
        )

        # Store initial results state to detect if developer set them manually
        initial_results = step.results

        # Call the developer-implemented process method
        process_output = process(task, sequence, step)

        # Process results using overridable method, respecting developer customization
        process_results(step, process_output, initial_results)

        log_structured(
          :debug,
          "Completed step execution",
          step_id: step.workflow_step_id,
          step_name: step.name,
          correlation_id: task.task_id,
          has_results: step.results.present?
        )

        process_output
      end

      # Developer extension point - implement your business logic here
      #
      # ✅  ALWAYS IMPLEMENT THIS METHOD IN SUBCLASSES
      # This is where you put your step's business logic. The framework will:
      # - Automatically publish step_started before calling this method
      # - Automatically publish step_completed after this method succeeds
      # - Automatically publish step_failed if this method raises an exception
      #
      # Return your results from this method - they will be stored in step.results
      # automatically via process_results(). You can override process_results() to
      # customize how the return value gets stored.
      #
      # @param task [Tasker::Task] The task being executed
      # @param sequence [Tasker::Types::StepSequence] The sequence of steps
      # @param step [Tasker::WorkflowStep] The current step being handled
      # @return [Object] The results of processing - will be stored in step.results
      # @raise [NotImplementedError] If not implemented by a subclass
      def process(task, sequence, step)
        raise NotImplementedError,
              'Subclasses must implement the process method. This is your extension point for business logic.'
      end

      # Process the output from process() method and store in step.results
      #
      # ✅ OVERRIDE THIS METHOD: To customize how process() output is stored
      #
      # This method provides a clean extension point for customizing how the return
      # value from your process() method gets stored in step.results. The default
      # behavior is to store the returned value directly.
      #
      # @param step [Tasker::WorkflowStep] The current step
      # @param process_output [Object] The return value from process() method
      # @param initial_results [Object] The value of step.results before process() was called
      # @return [void]
      def process_results(step, process_output, initial_results)
        # If developer already set step.results in their process() method, respect it
        if step.results != initial_results
          log_structured(
            :debug,
            "Developer set custom results in process() method",
            step_id: step.workflow_step_id,
            step_name: step.name
          )
          return
        end

        # Default behavior: store the return value from process()
        step.results = process_output
      end

      # Class method that step handlers can override to declare custom events
      #
      # ✅ OVERRIDE THIS METHOD: To declare custom events your step handler publishes
      #
      # Return an array of hashes where each hash defines a custom event:
      # - name: The event name (without namespace)
      # - description: Human-readable description of when this event is published
      #
      # Example:
      #   def self.custom_event_configuration
      #     [
      #       {
      #         name: 'payment.processed',
      #         description: 'Published when payment processing completes successfully'
      #       },
      #       {
      #         name: 'payment.risk_flagged',
      #         description: 'Published when payment is flagged for manual review'
      #       }
      #     ]
      #   end
      #
      # @return [Array<Hash>] Array of custom event definitions
      def self.custom_event_configuration
        []
      end

      protected

      # Access to configuration passed during initialization
      attr_reader :config
    end
  end
end
