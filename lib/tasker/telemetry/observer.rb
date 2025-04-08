# frozen_string_literal: true

module Tasker
  module Telemetry
    # Observer that connects lifecycle events to telemetry system
    class Observer
      # Initialize and register with lifecycle events system
      def initialize
        Tasker::LifecycleEvents.register_observer(self)
      end

      # Handle a lifecycle event by recording telemetry
      # @param event [String] The event name
      # @param context [Hash] The context data associated with the event
      def on_lifecycle_event(event, context)
        Tasker::Telemetry.record(event, context)
      end

      # Create a span for tracing execution
      # @param name [String] The span name
      # @param context [Hash] The context data associated with the span
      # @param block [Block] The block to execute within the span
      # @return [Proc] A procedure that executes the block within the span
      def trace_execution(name, context, &block)
        proc do
          Tasker::Telemetry.add_span(name, context, &block)
        end
      end

      # Start a trace for the given task
      # @param task [Tasker::Task] The task to trace
      def start_task_trace(task)
        Tasker::Telemetry.start_trace(
          "task.#{task.name}",
          { task_id: task.task_id, task_name: task.name }
        )
      end

      # End the current trace
      def end_task_trace
        Tasker::Telemetry.end_trace
      end

      class << self
        # Get or create the singleton instance
        # @return [Observer] The singleton instance
        def instance
          @instance ||= new
        end

        # Reset the singleton instance
        def reset_instance
          @instance = nil
        end
      end
    end
  end
end
