# typed: false
# frozen_string_literal: true

module Tasker
  class TaskRunnerJob < Tasker::ApplicationJob
    include Tasker::Concerns::StructuredLogging
    include Tasker::Concerns::EventPublisher

    queue_as :default
    retry_on StandardError, wait: 3.seconds, attempts: 3

    def handler_factory
      @handler_factory ||= Tasker::HandlerFactory.instance
    end

    def perform(task_id, correlation_id: nil)
      job_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      task = nil

      # Establish correlation ID for the entire job execution
      job_correlation_id = correlation_id || generate_correlation_id

      with_correlation_id(job_correlation_id) do
        log_structured(:info, 'TaskRunnerJob execution started',
                       task_id: task_id,
                       job_id: job_id,
                       correlation_id: job_correlation_id,
                       queue_name: queue_name,
                       attempt: executions + 1)

        # Find and validate task
        task = find_and_validate_task(task_id)
        return unless task

        # Publish task enqueue event for observability
        publish_task_enqueue(task,
                             job_id: job_id,
                             correlation_id: job_correlation_id,
                             queue_name: queue_name,
                             attempt: executions + 1)

        # Execute task with monitoring
        execute_task_with_monitoring(task, job_correlation_id, job_start_time)

        job_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - job_start_time

        # Safely get final status
        final_status = task&.reload&.status || 'unknown'

        log_performance_event('task_runner_job_execution', job_duration,
                              task_id: task_id,
                              job_id: job_id,
                              final_status: final_status,
                              correlation_id: job_correlation_id)

        log_structured(:info, 'TaskRunnerJob execution completed',
                       task_id: task_id,
                       job_id: job_id,
                       final_task_status: task&.status,
                       duration_ms: (job_duration * 1000).round(2),
                       correlation_id: job_correlation_id)
      end
    rescue StandardError => e
      job_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - job_start_time

      log_exception(e, context: {
                      task_id: task_id,
                      job_id: job_id,
                      correlation_id: job_correlation_id,
                      operation: 'task_runner_job_execution',
                      duration: job_duration,
                      attempt: executions + 1
                    })

      Rails.logger.error("TaskRunnerJob: Error processing task #{task_id}: #{e.message}")
      raise
    end

    private

    # Find and validate the task for execution
    #
    # @param task_id [String] The task ID to find
    # @return [Tasker::Task, nil] The task if found and valid, nil otherwise
    def find_and_validate_task(task_id)
      task = Tasker::Task.where(task_id: task_id).first

      unless task
        log_structured(:error, 'TaskRunnerJob: Task not found',
                       task_id: task_id,
                       job_id: job_id,
                       error: 'Task not found in database')
        return nil
      end

      log_structured(:debug, 'TaskRunnerJob: Task found and validated',
                     task_id: task_id,
                     task_name: task.name,
                     task_status: task.status,
                     job_id: job_id)

      task
    end

    # Execute the task with comprehensive monitoring
    #
    # @param task [Tasker::Task] The task to execute
    # @param job_correlation_id [String] The correlation ID for this job
    # @param job_start_time [Float] The job start time for duration calculation
    # @return [void]
    def execute_task_with_monitoring(task, job_correlation_id, _job_start_time)
      Rails.logger.info "TaskRunnerJob: Starting execution for task #{task.task_id}"

      log_task_event(task, :job_execution_started,
                     job_id: job_id,
                     correlation_id: job_correlation_id,
                     queue_name: queue_name,
                     attempt: executions + 1)

      # Get the appropriate task handler with timing
      handler_lookup_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      handler = handler_factory.get(task.name, namespace_name: task.namespace_name, version: task.version)
      handler_lookup_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - handler_lookup_start

      log_performance_event('handler_factory_lookup', handler_lookup_duration,
                            task_id: task.task_id,
                            task_name: task.name,
                            namespace_name: task.namespace_name,
                            version: task.version,
                            handler_class: handler.class.name)

      log_structured(:debug, 'TaskRunnerJob: Handler retrieved',
                     task_id: task.task_id,
                     handler_class: handler.class.name,
                     lookup_duration_ms: (handler_lookup_duration * 1000).round(2))

      # Execute the task handler with timing
      task_execution_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      handler.handle(task)
      task_execution_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - task_execution_start

      log_performance_event('task_handler_execution', task_execution_duration,
                            task_id: task.task_id,
                            task_name: task.name,
                            handler_class: handler.class.name)

      # Validate task completion
      validate_task_completion(task, job_correlation_id, task_execution_duration)

      Rails.logger.info "TaskRunnerJob: Completed execution for task #{task.task_id}"
    end

    # Validate that the task completed successfully
    #
    # @param task [Tasker::Task] The task to validate
    # @param job_correlation_id [String] The correlation ID for this job
    # @param task_execution_duration [Float] How long the task execution took
    # @return [void]
    # @raise [RuntimeError] If task did not complete successfully
    def validate_task_completion(task, job_correlation_id, task_execution_duration)
      task.reload

      log_task_event(task, :job_execution_completed,
                     job_id: job_id,
                     final_status: task.status,
                     correlation_id: job_correlation_id,
                     execution_duration_ms: (task_execution_duration * 1000).round(2))

      if task.status == Tasker::Constants::TaskStatuses::COMPLETE
        log_structured(:info, 'TaskRunnerJob: Task completed successfully',
                       task_id: task.task_id,
                       final_status: task.status,
                       execution_duration_ms: (task_execution_duration * 1000).round(2))
      else
        error_message = "Task processing failed for task #{task.task_id} - final status: #{task.status}"

        log_task_event(task, :job_execution_failed,
                       job_id: job_id,
                       final_status: task.status,
                       error: error_message,
                       correlation_id: job_correlation_id)

        Rails.logger.error("TaskRunnerJob: #{error_message}")
        raise "TaskRunnerJob: #{error_message}"
      end
    end

    # Generate a correlation ID for job execution
    #
    # @return [String] A unique correlation ID
    def generate_correlation_id
      if defined?(Tasker::Logging::CorrelationIdGenerator)
        Tasker::Logging::CorrelationIdGenerator.generate
      else
        "job_#{SecureRandom.hex(8)}"
      end
    end
  end
end
