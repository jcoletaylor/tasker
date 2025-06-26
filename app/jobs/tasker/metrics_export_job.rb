# frozen_string_literal: true

module Tasker
  # ActiveJob for exporting metrics with distributed coordination
  #
  # **Phase 4.2.2.3.3**: Thin wrapper around MetricsExportService that handles
  # ActiveJob concerns (queueing, retries, timeouts) while delegating the actual
  # export business logic to the service.
  #
  # Key Features:
  # - Rails ActiveJob integration for any backend (Sidekiq, SQS, etc.)
  # - Distributed coordination through ExportCoordinator
  # - Retry handling with exponential backoff
  # - Timeout protection
  # - Comprehensive logging
  #
  # @example Scheduled by ExportCoordinator
  #   MetricsExportJob.set(wait_until: 5.minutes.from_now).perform_later(
  #     format: :prometheus,
  #     coordinator_instance: "web-1-12345",
  #     timing: { export_time: Time.current + 5.minutes }
  #   )
  #
  class MetricsExportJob < ApplicationJob
    include Tasker::Concerns::StructuredLogging

    # Configure job retry behavior with exponential backoff
    # This replaces the sleep-based retry in ExportCoordinator
    retry_on StandardError,
             wait: :exponentially_longer,
             attempts: 3,
             queue: :metrics_export_retry

    # Use separate queue for metrics export to avoid blocking other jobs
    queue_as :metrics_export

    # Job timeout to prevent hanging exports
    around_perform :with_timeout

    # @param format [Symbol] Export format (:prometheus, :json, :csv)
    # @param coordinator_instance [String] ExportCoordinator instance identifier
    # @param scheduled_by [String] Who scheduled this job
    # @param timing [Hash] Export timing information
    # @param include_instances [Boolean] Include per-instance metrics breakdown
    def perform(format:, coordinator_instance:, scheduled_by: nil, timing: nil, include_instances: false)
      @format = format.to_sym
      @coordinator_instance = coordinator_instance
      @scheduled_by = scheduled_by
      @timing = timing
      @include_instances = include_instances
      @job_start_time = Time.current

      log_job_started

      # Get metrics data from coordinator
      coordinator = Tasker::Telemetry::ExportCoordinator.instance
      export_result = coordinator.execute_coordinated_export(
        format: @format,
        include_instances: @include_instances
      )

      if export_result[:success]
        # Delegate actual export to service
        service_result = export_with_service(export_result[:result])
        log_job_completed(service_result)
      else
        # Export coordination failed
        handle_failed_coordination(export_result)
      end
    rescue StandardError => e
      log_job_error(e)

      # Extend cache TTL before retry to prevent data loss
      extend_cache_ttl_for_retry

      raise # Re-raise to trigger ActiveJob retry logic
    end

    private

    # Export metrics using the MetricsExportService
    #
    # @param metrics_data [Hash] Metrics data from coordinator
    # @return [Hash] Export service result
    def export_with_service(metrics_data)
      service = Tasker::Telemetry::MetricsExportService.new

      export_context = {
        job_id: job_id,
        coordinator_instance: @coordinator_instance,
        scheduled_by: @scheduled_by,
        timing: @timing
      }

      service.export_metrics(
        format: @format,
        metrics_data: metrics_data,
        context: export_context
      )
    end

    # Handle failed export coordination
    #
    # @param export_result [Hash] Export result with error information
    def handle_failed_coordination(export_result)
      log_coordination_failure(export_result)

      # If this is a lock timeout, it's not necessarily an error
      # Another container is handling the export
      unless export_result[:error]&.include?('lock timeout')
        raise StandardError, "Export coordination failed: #{export_result[:error]}"
      end

      log_concurrent_export_detected

      # Actual coordination failure - raise error to trigger retry
    end

    # Timeout wrapper for job execution
    #
    # @param job [ActiveJob] The job being executed
    # @yield Block to execute with timeout
    def with_timeout(_job, &)
      timeout_duration = job_timeout_duration

      Timeout.timeout(timeout_duration, &)
    rescue Timeout::Error
      log_job_timeout(timeout_duration)
      raise StandardError, "Export job timed out after #{timeout_duration} seconds"
    end

    # Get job timeout duration from configuration
    #
    # @return [Integer] Timeout duration in seconds
    def job_timeout_duration
      prometheus_config = begin
        Tasker.configuration.telemetry.prometheus
      rescue StandardError
        {}
      end
      prometheus_config[:job_timeout] || 5.minutes
    end

    # Extend cache TTL to prevent data loss during job retry
    #
    # Uses the job's executions count to calculate appropriate extension
    def extend_cache_ttl_for_retry
      return unless defined?(executions) && executions > 1

      # Calculate extension based on retry attempt and expected delay
      retry_delay = calculate_job_retry_delay(executions)
      safety_margin = 1.minute
      extension_duration = retry_delay + safety_margin

      coordinator = Tasker::Telemetry::ExportCoordinator.instance
      result = coordinator.extend_cache_ttl(extension_duration)

      log_ttl_extension_for_retry(extension_duration, result)
    rescue StandardError => e
      log_ttl_extension_error(e)
      # Don't fail the job if TTL extension fails
    end

    # Calculate expected retry delay for current execution attempt
    #
    # @param execution_count [Integer] Current execution attempt (1-based)
    # @return [Duration] Expected delay until next retry
    def calculate_job_retry_delay(execution_count)
      # ActiveJob exponentially_longer uses: attempt ** 4 + 2 seconds
      # But we use a more conservative estimate based on our config
      base_delay = 30.seconds
      (base_delay * (2**(execution_count - 2))).clamp(30.seconds, 10.minutes)
    end

    # Logging methods for job execution events

    def log_job_started
      log_structured(:info, 'Metrics export job started',
                     job_id: job_id,
                     format: @format,
                     coordinator_instance: @coordinator_instance,
                     scheduled_by: @scheduled_by,
                     timing: @timing,
                     include_instances: @include_instances)
    end

    def log_job_completed(service_result)
      duration = Time.current - @job_start_time

      log_structured(:info, 'Metrics export job completed',
                     job_id: job_id,
                     format: @format,
                     success: service_result[:success],
                     duration: duration,
                     service_duration: service_result[:duration],
                     exported_at: service_result[:exported_at])
    end

    def log_job_error(error)
      # Get first 5 backtrace lines and pad to exactly 5 elements with nil
      backtrace_lines = error.backtrace&.first(5) || []
      backtrace = backtrace_lines + Array.new(5 - backtrace_lines.size, nil)

      log_structured(:error, 'Metrics export job error',
                     job_id: job_id,
                     format: @format,
                     error: error.message,
                     error_class: error.class.name,
                     backtrace: backtrace)
    end

    def log_job_timeout(timeout_duration)
      log_structured(:error, 'Metrics export job timeout',
                     job_id: job_id,
                     format: @format,
                     timeout_duration: timeout_duration)
    end

    def log_coordination_failure(export_result)
      log_structured(:warn, 'Export coordination failed',
                     job_id: job_id,
                     format: @format,
                     error: export_result[:error],
                     attempts: export_result[:attempts])
    end

    def log_concurrent_export_detected
      log_structured(:info, 'Concurrent export detected - skipping',
                     job_id: job_id,
                     format: @format,
                     reason: 'another_container_exporting')
    end

    def log_ttl_extension_for_retry(extension_duration, result)
      log_structured(:info, 'Cache TTL extended for job retry',
                     job_id: job_id,
                     format: @format,
                     execution_attempt: defined?(executions) ? executions : 1,
                     extension_duration: extension_duration,
                     ttl_extension_success: result[:success],
                     metrics_extended: result[:metrics_extended])
    end

    def log_ttl_extension_error(error)
      log_structured(:warn, 'Failed to extend cache TTL for retry',
                     job_id: job_id,
                     format: @format,
                     error: error.message,
                     note: 'Job will continue but metrics may expire during retry delay')
    end
  end
end
