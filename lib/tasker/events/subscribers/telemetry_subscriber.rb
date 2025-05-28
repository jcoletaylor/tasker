# frozen_string_literal: true

module Tasker
  module Events
    module Subscribers
      # TelemetrySubscriber handles telemetry events for observability
      #
      # This subscriber demonstrates dry-events best practices by:
      # - Keeping event handlers simple and focused
      # - Using minimal ceremony for event processing
      # - Integrating with existing instrumentation
      class TelemetrySubscriber
        # Subscribe to all events we care about
        #
        # @param publisher [Tasker::Events::Publisher] The event publisher
        def self.subscribe(publisher)
          subscriber = new

          # Task lifecycle events
          publisher.subscribe('task.start_requested', &subscriber.method(:handle_task_started))
          publisher.subscribe('task.completed', &subscriber.method(:handle_task_completed))
          publisher.subscribe('task.failed', &subscriber.method(:handle_task_failed))
          publisher.subscribe('task.cancelled', &subscriber.method(:handle_task_cancelled))

          # Step lifecycle events
          publisher.subscribe('step.execution_requested', &subscriber.method(:handle_step_started))
          publisher.subscribe('step.completed', &subscriber.method(:handle_step_completed))
          publisher.subscribe('step.failed', &subscriber.method(:handle_step_failed))
          publisher.subscribe('step.backoff', &subscriber.method(:handle_step_backoff))

          # Workflow events
          publisher.subscribe('workflow.iteration_started', &subscriber.method(:handle_workflow_iteration))
          publisher.subscribe('workflow.viable_steps_batch_processed', &subscriber.method(:handle_batch_processed))
        end

        # Handle task start events
        def handle_task_started(event)
          record_metric('task.started', {
                          task_id: event[:task_id],
                          task_name: event[:task_name]
                        })
        end

        # Handle task completion events
        def handle_task_completed(event)
          record_metric('task.completed', {
                          task_id: event[:task_id],
                          task_name: event[:task_name],
                          duration: calculate_duration(event)
                        })
        end

        # Handle task failure events
        def handle_task_failed(event)
          record_metric('task.failed', {
                          task_id: event[:task_id],
                          task_name: event[:task_name],
                          error: event[:error]
                        })
        end

        # Handle task cancellation events
        def handle_task_cancelled(event)
          record_metric('task.cancelled', {
                          task_id: event[:task_id],
                          task_name: event[:task_name]
                        })
        end

        # Handle step start events
        def handle_step_started(event)
          record_metric('step.started', {
                          task_id: event[:task_id],
                          step_id: event[:step_id],
                          step_name: event[:step_name]
                        })
        end

        # Handle step completion events
        def handle_step_completed(event)
          record_metric('step.completed', {
                          task_id: event[:task_id],
                          step_id: event[:step_id],
                          step_name: event[:step_name],
                          execution_duration: event[:execution_duration]
                        })
        end

        # Handle step failure events
        def handle_step_failed(event)
          record_metric('step.failed', {
                          task_id: event[:task_id],
                          step_id: event[:step_id],
                          step_name: event[:step_name],
                          error: event[:error_message],
                          attempt_number: event[:attempt_number]
                        })
        end

        # Handle step backoff events
        def handle_step_backoff(event)
          record_metric('step.backoff', {
                          task_id: event[:task_id],
                          step_id: event[:step_id],
                          backoff_seconds: event[:backoff_seconds],
                          backoff_type: event[:backoff_type]
                        })
        end

        # Handle workflow iteration events
        def handle_workflow_iteration(event)
          record_metric('workflow.iteration', {
                          task_id: event[:task_id],
                          iteration: event[:iteration]
                        })
        end

        # Handle batch processing events
        def handle_batch_processed(event)
          record_metric('workflow.batch_processed', {
                          task_id: event[:task_id],
                          step_count: event[:count]
                        })
        end

        private

        # Record a metric using the instrumentation system
        def record_metric(metric_name, attributes = {})
          return unless defined?(Tasker::Instrumentation)

          Tasker::Instrumentation.record_event("tasker.#{metric_name}", attributes)
        rescue StandardError => e
          Rails.logger.error("Failed to record telemetry metric #{metric_name}: #{e.message}")
        end

        # Calculate duration from event timestamps
        def calculate_duration(event)
          return nil unless event[:started_at] && event[:completed_at]

          Time.zone.parse(event[:completed_at]) - Time.zone.parse(event[:started_at])
        rescue StandardError
          nil
        end
      end
    end
  end
end
