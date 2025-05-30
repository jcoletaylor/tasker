# frozen_string_literal: true

require_relative 'events/bus'

module Tasker
  # Simplified lifecycle events using dry-events
  #
  # This module provides a clean event firing interface using dry-events
  # publisher/subscriber patterns for decoupled communication.
  module LifecycleEvents
    # Event namespace for ActiveSupport::Notifications compatibility
    EVENT_NAMESPACE = 'tasker'

    class << self
      # Get the global event bus
      #
      # @return [Tasker::Events::Bus] The event bus instance
      def bus
        @bus ||= begin
          bus_instance = Tasker::Events::Bus.instance
          bus_instance.setup_default_subscribers
          bus_instance
        end
      end

      # Fire a lifecycle event with associated context
      #
      # @param event [String] The event name
      # @param context [Hash] The context data associated with the event
      # @yield [void] Optional block to instrument
      # @return [Object, nil] The result of the block if given, otherwise nil
      def fire(event, context = {})
        Rails.logger.debug { "LifecycleEvent fired: #{event} with context: #{context.inspect}" }

        # Create namespaced event name for ActiveSupport::Notifications
        namespaced_event = "#{EVENT_NAMESPACE}.#{event}"

        if block_given?
          # Execute block and publish event with result
          result = nil

          # Use ActiveSupport::Notifications.instrument for timing
          ActiveSupport::Notifications.instrument(namespaced_event, context) do
            result = yield
          end

          result
        else
          # For non-block events, use instrument with empty block to ensure proper timing
          ActiveSupport::Notifications.instrument(namespaced_event, context) do
            # Empty block - just fires the event with timing
          end

          nil
        end
      end

      # Fire an event with span-based tracing
      #
      # This is an alias for backward compatibility that behaves the same
      # as the regular fire method.
      #
      # @param event [String] The event name
      # @param context [Hash] The context data associated with the event
      # @yield [void] Optional block to instrument
      # @return [Object, nil] The result of the block if given, otherwise nil
      def fire_with_span(event, context = {}, &)
        fire(event, context, &)
      end

      # Helper to fire an event with an exception
      #
      # @param event [String] The event name
      # @param exception [Exception] The exception to include
      # @param context [Hash] Additional context data
      # @return [void]
      def fire_error(event, exception, context = {})
        error_context = context.merge(
          exception: [exception.class.name, exception.message],
          exception_object: exception,
          backtrace: exception.backtrace&.join("\n")
        )

        fire(event, error_context)
      end

      # Fire a task lifecycle event
      #
      # @param event [String] The event name
      # @param task [Object] The task object
      # @param metadata [Hash] Additional metadata
      def fire_task_event(event, task, metadata = {})
        bus.publish_task_event(event, task, metadata)
      end

      # Fire a step lifecycle event
      #
      # @param event [String] The event name
      # @param step [Object] The step object
      # @param metadata [Hash] Additional metadata
      def fire_step_event(event, step, metadata = {})
        bus.publish_step_event(event, step, metadata)
      end

      # Fire a workflow orchestration event
      #
      # @param event [String] The event name
      # @param context [Hash] The event context
      def fire_workflow_event(event, context = {})
        bus.publish_workflow_event(event, context)
      end

      # Subscribe to events (delegates to bus)
      #
      # @param event_name [String] The event to subscribe to
      # @param callable [Proc, Method] The callback
      def subscribe(event_name, callable = nil, &)
        bus.subscribe(event_name, callable, &)
      end

      # Subscribe an object with event handling methods
      #
      # @param subscriber [Object] Object with event handling methods
      delegate :subscribe_object, to: :bus
    end

    # Event names - updated to use modern constants
    module Events
      # Task-related lifecycle events
      module Task
        # Fired when a task is initialized
        INITIALIZE = 'task.initialize_requested'
        # Fired when a task is started
        START = 'task.start_requested'
        # Task state events (use modern constants)
        COMPLETE = Tasker::Constants::TaskEvents::COMPLETED    # 'task.completed'
        ERROR = Tasker::Constants::TaskEvents::FAILED          # 'task.failed'
        # Process tracking events (use ObservabilityEvents)
        HANDLE = Tasker::Constants::ObservabilityEvents::Task::HANDLE      # 'task.handle'
        ENQUEUE = Tasker::Constants::ObservabilityEvents::Task::ENQUEUE    # 'task.enqueue'
        FINALIZE = Tasker::Constants::ObservabilityEvents::Task::FINALIZE  # 'task.finalize'
      end

      # Step-related lifecycle events
      module Step
        # Step state events (use modern constants)
        COMPLETE = Tasker::Constants::StepEvents::COMPLETED         # 'step.completed'
        ERROR = Tasker::Constants::StepEvents::FAILED              # 'step.failed'
        RETRY = Tasker::Constants::StepEvents::RETRY_REQUESTED      # 'step.retry_requested'
        # Process tracking events (use ObservabilityEvents)
        FIND_VIABLE = Tasker::Constants::ObservabilityEvents::Step::FIND_VIABLE        # 'step.find_viable'
        HANDLE = Tasker::Constants::ObservabilityEvents::Step::HANDLE                  # 'step.handle'
        BACKOFF = Tasker::Constants::ObservabilityEvents::Step::BACKOFF                # 'step.backoff'
        SKIP = Tasker::Constants::ObservabilityEvents::Step::SKIP                      # 'step.skip'
        MAX_RETRIES_REACHED = Tasker::Constants::ObservabilityEvents::Step::MAX_RETRIES_REACHED  # 'step.max_retries_reached'
      end
    end
  end
end
