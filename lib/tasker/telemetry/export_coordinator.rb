# frozen_string_literal: true

module Tasker
  module Telemetry
    # Coordinates metric exports with TTL-aware scheduling and distributed locking
    #
    # **Phase 4.2.2.3.3**: Export coordination prevents data loss during cache TTL
    # expiration while maintaining efficient scheduling and cross-container coordination.
    #
    # Key Features:
    # - Dynamic TTL-aware export scheduling with safety margins
    # - Distributed locking using Rails.cache atomic operations
    # - Job runner architecture separating collection from export
    # - Configurable retry limits with TTL extension recovery
    #
    # @example Basic usage
    #   coordinator = ExportCoordinator.new
    #   coordinator.schedule_export(format: :prometheus, safety_margin: 1.minute)
    #
    # @example With custom configuration
    #   coordinator = ExportCoordinator.new(
    #     retention_window: 10.minutes,
    #     max_retries: 5,
    #     export_timeout: 2.minutes
    #   )
    #
    class ExportCoordinator
      include Tasker::Concerns::StructuredLogging

      # Default configuration values
      DEFAULT_CONFIG = {
        retention_window: 5.minutes,
        safety_margin: 1.minute,
        export_timeout: 2.minutes,
        max_retries: 3,
        retry_backoff_base: 30.seconds,
        lock_timeout: 5.minutes
      }.freeze

      attr_reader :config, :instance_id, :cache_capabilities

      # Initialize export coordinator with configuration
      #
      # @param config [Hash] Export coordination configuration
      # @option config [Duration] :retention_window Cache retention time
      # @option config [Duration] :safety_margin Time buffer before TTL expiry
      # @option config [Duration] :export_timeout Maximum export job duration
      # @option config [Integer] :max_retries Maximum retry attempts
      # @option config [Duration] :retry_backoff_base Base delay for exponential backoff
      # @option config [Duration] :lock_timeout Distributed lock timeout
      def initialize(config = {})
        @config = DEFAULT_CONFIG.merge(config)
        @instance_id = generate_instance_id
        @metrics_backend = MetricsBackend.instance
        @cache_capabilities = detect_cache_capabilities

        log_coordinator_initialization
      end

      # Schedule export with dynamic TTL-aware timing
      #
      # Calculates optimal export timing based on cache TTL and safety margins,
      # ensuring exports complete before metrics expire from cache.
      #
      # @param format [Symbol] Export format (:prometheus, :json, :csv)
      # @param safety_margin [Duration] Override default safety margin
      # @return [Hash] Scheduling result with timing information
      def schedule_export(format: :prometheus, safety_margin: nil)
        safety_margin ||= @config[:safety_margin]

        # Calculate dynamic export timing
        timing = calculate_export_timing(safety_margin)

        # Check if TTL extension is needed
        extend_cache_ttl(timing[:extension_duration]) if timing[:needs_ttl_extension]

        # Schedule the export job
        job_result = schedule_export_job(format, timing)

        log_export_scheduled(format, timing, job_result)

        {
          success: true,
          format: format,
          scheduled_at: timing[:export_time],
          job_id: job_result[:job_id],
          timing: timing,
          coordinator_instance: @instance_id
        }
      rescue StandardError => e
        log_export_scheduling_error(e, format)
        { success: false, error: e.message }
      end

      # Execute export with distributed coordination
      #
      # Handles the actual export execution with distributed locking to prevent
      # concurrent exports from multiple containers. Uses capability-aware locking.
      #
      # @param format [Symbol] Export format
      # @param include_instances [Boolean] Include per-instance breakdown
      # @return [Hash] Export result with metrics and status
      def execute_coordinated_export(format:, include_instances: false)
        with_distributed_export_lock do
          execute_export_with_recovery(format, include_instances)
        end
      rescue DistributedLockTimeoutError => e
        log_export_lock_timeout(e)
        { success: false, error: 'Export lock timeout - another container is exporting' }
      rescue StandardError => e
        log_export_execution_error(e, format)
        { success: false, error: e.message }
      end

      # Extend cache TTL for all metrics to prevent data loss
      #
      # Used when export jobs are delayed or failed, extending the TTL to provide
      # additional time for successful export completion.
      #
      # @param extension_duration [Duration] How much to extend TTL
      # @return [Hash] Extension result with affected metrics count
      def extend_cache_ttl(extension_duration)
        return { success: false, reason: 'TTL extension not supported' } unless ttl_extension_supported?

        metrics_extended = 0

        @metrics_backend.all_metrics.each_key do |key|
          cache_key = @metrics_backend.send(:build_cache_key, key)
          current_data = Rails.cache.read(cache_key)

          next unless current_data

          Rails.cache.write(cache_key, current_data,
                            expires_in: @config[:retention_window] + extension_duration)
          metrics_extended += 1
        end

        log_ttl_extension(extension_duration, metrics_extended)

        { success: true, extension_duration: extension_duration, metrics_extended: metrics_extended }
      end

      private

      # Calculate optimal export timing based on cache TTL and safety margins
      #
      # @param safety_margin [Duration] Safety buffer before TTL expiry
      # @return [Hash] Timing information including export time and TTL extension needs
      def calculate_export_timing(safety_margin)
        current_time = Time.current

        # Calculate when current metrics will expire from cache
        ttl_expiry_time = current_time + @config[:retention_window]

        # Calculate desired export completion time (before TTL expiry)
        desired_completion_time = ttl_expiry_time - safety_margin

        # Account for job execution time
        latest_start_time = desired_completion_time - @config[:export_timeout]

        # Determine if we need to extend TTL
        needs_extension = latest_start_time <= current_time

        if needs_extension
          # Calculate how much to extend TTL
          extension_needed = (current_time - latest_start_time) + safety_margin
          export_time = current_time + 30.seconds # Small delay for immediate execution

          {
            export_time: export_time,
            ttl_expiry_time: ttl_expiry_time + extension_needed,
            needs_ttl_extension: true,
            extension_duration: extension_needed,
            scheduling_reason: 'immediate_with_ttl_extension'
          }
        else
          {
            export_time: latest_start_time,
            ttl_expiry_time: ttl_expiry_time,
            needs_ttl_extension: false,
            scheduling_reason: 'optimal_timing'
          }
        end
      end

      # Schedule export job using Rails ActiveJob
      #
      # @param format [Symbol] Export format
      # @param timing [Hash] Timing information from calculate_export_timing
      # @return [Hash] Job scheduling result
      def schedule_export_job(format, timing)
        job_args = {
          format: format,
          coordinator_instance: @instance_id,
          scheduled_by: 'export_coordinator',
          timing: timing
        }

        # Schedule job with calculated timing
        job = if timing[:export_time] <= 30.seconds.from_now
                # Immediate execution
                MetricsExportJob.set(queue: :metrics_export).perform_later(**job_args)
              else
                # Delayed execution
                MetricsExportJob.set(wait_until: timing[:export_time], queue: :metrics_export).perform_later(**job_args)
              end

        { job_id: job.job_id, scheduled_for: timing[:export_time] }
      end

      # Execute export with distributed locking
      #
      # @param timeout [Duration] Lock timeout duration
      # @yield Block to execute while holding the lock
      # @return [Object] Result of the yielded block
      # @raise [DistributedLockTimeoutError] If lock cannot be acquired
      def with_distributed_export_lock(timeout: nil)
        timeout ||= @config[:lock_timeout]
        lock_key = 'tasker:metrics:export_lock'

        # Attempt to acquire distributed lock using Rails.cache atomic operations
        lock_acquired = Rails.cache.write(lock_key, @instance_id,
                                          expires_in: timeout,
                                          unless_exist: true)

        unless lock_acquired
          raise DistributedLockTimeoutError, 'Could not acquire export lock - another export in progress'
        end

        begin
          log_export_lock_acquired(lock_key, timeout)
          yield
        ensure
          Rails.cache.delete(lock_key)
          log_export_lock_released(lock_key)
        end
      end

      # Execute single export attempt without retry logic
      #
      # Retry logic is now handled by the job queue system with proper
      # job scheduling and exponential backoff delays.
      #
      # @param format [Symbol] Export format
      # @param include_instances [Boolean] Include per-instance breakdown
      # @return [Hash] Export result
      def execute_export_with_recovery(format, include_instances)
        # Execute the actual export
        export_result = @metrics_backend.export_distributed_metrics(include_instances: include_instances)

        log_export_success(format, 1, export_result)
        {
          success: true,
          format: format,
          attempts: 1,
          result: export_result,
          exported_at: Time.current.iso8601
        }
      rescue StandardError => e
        log_export_attempt_failed(format, 1, e)

        # Extend cache TTL to prevent data loss during retry delay
        extend_cache_ttl(@config[:retry_backoff_base] + @config[:safety_margin])

        # Re-raise error to trigger job retry mechanism
        raise e
      end

      # Check if TTL extension is supported by current cache store
      #
      # @return [Boolean] True if TTL extension is supported
      def ttl_extension_supported?
        !!(@cache_capabilities[:ttl_inspection] || @cache_capabilities[:distributed])
      end

      # Generate unique instance identifier
      #
      # @return [String] Instance identifier
      def generate_instance_id
        hostname = begin
          ENV['HOSTNAME'] || Socket.gethostname
        rescue StandardError
          'unknown'
        end
        "#{hostname}-#{Process.pid}-#{Time.current.to_i}"
      end

      # Detect cache store capabilities
      #
      # @return [Hash] Cache capabilities
      def detect_cache_capabilities
        @metrics_backend.send(:detect_cache_capabilities)
      end

      # Custom error for distributed lock timeouts
      class DistributedLockTimeoutError < StandardError; end

      # Logging methods for export coordination events

      def log_coordinator_initialization
        log_structured(:info, 'Export coordinator initialized',
                       instance_id: @instance_id,
                       cache_capabilities: @cache_capabilities,
                       config: @config)
      end

      def log_export_scheduled(format, timing, job_result)
        log_structured(:info, 'Export scheduled',
                       format: format,
                       export_time: timing[:export_time],
                       scheduling_reason: timing[:scheduling_reason],
                       needs_ttl_extension: timing[:needs_ttl_extension],
                       job_id: job_result[:job_id])
      end

      def log_export_scheduling_error(error, format)
        log_structured(:error, 'Export scheduling failed',
                       format: format,
                       error: error.message,
                       backtrace: error.backtrace&.first(5))
      end

      def log_export_lock_acquired(lock_key, timeout)
        log_structured(:debug, 'Export lock acquired',
                       lock_key: lock_key,
                       timeout: timeout,
                       instance_id: @instance_id)
      end

      def log_export_lock_released(lock_key)
        log_structured(:debug, 'Export lock released',
                       lock_key: lock_key,
                       instance_id: @instance_id)
      end

      def log_export_lock_timeout(error)
        log_structured(:warn, 'Export lock acquisition timeout',
                       error: error.message,
                       instance_id: @instance_id)
      end

      def log_ttl_extension(extension_duration, metrics_extended)
        log_structured(:warn, 'Cache TTL extended to prevent data loss',
                       extension_duration: extension_duration,
                       metrics_extended: metrics_extended,
                       reason: 'export_delay_recovery')
      end

      def log_export_success(format, attempts, export_result)
        log_structured(:info, 'Export completed successfully',
                       format: format,
                       attempts: attempts,
                       metrics_count: export_result[:metrics]&.size || 0,
                       instance_id: @instance_id)
      end

      def log_export_attempt_failed(format, attempt, error)
        log_structured(:warn, 'Export attempt failed',
                       format: format,
                       attempt: attempt,
                       error: error.message,
                       instance_id: @instance_id)
      end

      def log_export_execution_error(error, format)
        log_structured(:error, 'Export execution error',
                       format: format,
                       error: error.message,
                       backtrace: error.backtrace&.first(5),
                       instance_id: @instance_id)
      end
    end
  end
end
