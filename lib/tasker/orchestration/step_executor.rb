# frozen_string_literal: true

require 'concurrent'
require_relative '../concerns/idempotent_state_transitions'
require_relative '../concerns/structured_logging'
require_relative '../concerns/event_publisher'
require_relative '../types/step_sequence'
require_relative 'future_state_analyzer'

module Tasker
  module Orchestration
    # StepExecutor handles the execution of workflow steps with concurrent processing
    #
    # This class provides the implementation for step execution while preserving
    # the original concurrent processing capabilities using concurrent-ruby.
    # It fires lifecycle events for observability.
    #
    # Enhanced with structured logging and performance monitoring for production observability.
    class StepExecutor
      include Tasker::Concerns::IdempotentStateTransitions
      include Tasker::Concerns::EventPublisher
      include Tasker::Concerns::StructuredLogging

      # Configuration-driven execution settings
      # These delegate to Tasker.configuration.execution for configurable values
      # while maintaining architectural constants for Ruby-specific optimizations

      def execution_config
        @execution_config ||= Tasker.configuration.execution
      end

      # Execute a collection of viable steps
      #
      # This method preserves the original concurrent processing logic while
      # adding observability through lifecycle events and structured logging.
      #
      # @param task [Tasker::Task] The task containing the steps
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @param viable_steps [Array<Tasker::WorkflowStep>] Steps ready for execution
      # @param task_handler [Object] The task handler instance
      # @return [Array<Tasker::WorkflowStep>] Successfully processed steps
      def execute_steps(task, sequence, viable_steps, task_handler)
        return [] if viable_steps.empty?

        execution_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # Always use concurrent processing - sequential mode has been deprecated
        processing_mode = 'concurrent'

        log_orchestration_event('step_batch_execution', :started,
                                task_id: task.task_id,
                                step_count: viable_steps.size,
                                processing_mode: processing_mode,
                                step_names: viable_steps.map(&:name))

        # Fire observability event through orchestrator
        publish_steps_execution_started(
          task,
          step_count: viable_steps.size,
          processing_mode: processing_mode
        )

        # Always use concurrent processing with dynamic concurrency optimization
        processed_steps = execute_steps_concurrently_with_monitoring(task, sequence, viable_steps, task_handler)

        execution_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - execution_start_time
        successful_count = processed_steps.count do |s|
          s&.status == Tasker::Constants::WorkflowStepStatuses::COMPLETE
        end

        # Log performance metrics
        log_performance_event('step_batch_execution', execution_duration,
                              task_id: task.task_id,
                              step_count: viable_steps.size,
                              processed_count: processed_steps.size,
                              successful_count: successful_count,
                              failure_count: processed_steps.size - successful_count,
                              processing_mode: processing_mode)

        # Fire completion event through orchestrator
        publish_steps_execution_completed(
          task,
          processed_count: processed_steps.size,
          successful_count: successful_count
        )

        log_orchestration_event('step_batch_execution', :completed,
                                task_id: task.task_id,
                                processed_count: processed_steps.size,
                                successful_count: successful_count,
                                failure_count: processed_steps.size - successful_count,
                                duration_ms: (execution_duration * 1000).round(2))

        processed_steps.compact
      end

      # Calculate optimal concurrency based on system health and resources
      #
      # This method dynamically determines the maximum number of steps that can be
      # executed concurrently based on current system load, database connections,
      # and other health metrics. Now enhanced with ConnectionPoolIntelligence
      # for Rails-aware connection management.
      #
      # @return [Integer] Optimal number of concurrent steps (between configured min and max)
      def max_concurrent_steps
        # Return cached value if still valid
        cache_duration = execution_config.concurrency_cache_duration.seconds
        if @max_concurrent_steps && @concurrency_calculated_at &&
           (Time.current - @concurrency_calculated_at) < cache_duration
          return @max_concurrent_steps
        end

        # Calculate new concurrency level using enhanced intelligence
        @max_concurrent_steps = calculate_optimal_concurrency
        @concurrency_calculated_at = Time.current

        @max_concurrent_steps
      end

      # Handle viable steps discovered event
      #
      # Convenience method for event-driven workflows that takes an event payload
      # and executes the discovered steps.
      #
      # @param event [Hash] Event payload with task_id, step_ids, and processing_mode
      def handle_viable_steps_discovered(event)
        task_id = event[:task_id]
        step_ids = event[:step_ids] || []

        return [] if step_ids.empty?

        with_correlation_id(event[:correlation_id]) do
          log_orchestration_event('event_driven_execution', :started,
                                  task_id: task_id,
                                  step_ids: step_ids,
                                  trigger: 'viable_steps_discovered')

          task = Tasker::Task.find(task_id)
          task_handler = Tasker::HandlerFactory.instance.get(task.name)
          sequence = Tasker::Orchestration::StepSequenceFactory.get_sequence(task, task_handler)
          viable_steps = task.workflow_steps.where(workflow_step_id: step_ids)

          execute_steps(task, sequence, viable_steps, task_handler)
        end
      end

      # Execute a single step with state machine transitions and error handling
      #
      # Enhanced with structured logging and performance monitoring.
      #
      # @param task [Tasker::Task] The task containing the step
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @param step [Tasker::WorkflowStep] The step to execute
      # @param task_handler [Object] The task handler instance
      # @return [Tasker::WorkflowStep, nil] The executed step or nil if failed
      def execute_single_step(task, sequence, step, task_handler)
        step_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        log_step_event(step, :execution_starting,
                       task_id: task.task_id,
                       step_status: step.status,
                       attempt_count: step.attempts)

        # Guard clauses - fail fast if preconditions aren't met
        return nil unless validate_step_preconditions_with_logging(step)
        return nil unless ensure_step_has_initial_state_with_logging(step)
        return nil unless step_ready_for_execution_with_logging?(step)

        # Main execution workflow with monitoring
        result = execute_step_workflow_with_monitoring(task, sequence, step, task_handler, step_start_time)

        step_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - step_start_time

        if result
          log_performance_event('single_step_execution', step_duration,
                                task_id: task.task_id,
                                step_id: step.workflow_step_id,
                                step_name: step.name,
                                result: 'success',
                                attempt_count: step.attempts)
        else
          log_performance_event('single_step_execution', step_duration,
                                task_id: task.task_id,
                                step_id: step.workflow_step_id,
                                step_name: step.name,
                                result: 'failure',
                                attempt_count: step.attempts)
        end

        result
      rescue StandardError => e
        step_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - step_start_time

        # Log unexpected errors that occur outside the normal workflow
        step_id = step&.workflow_step_id
        log_exception(e, context: {
                        step_id: step_id,
                        task_id: task&.task_id,
                        operation: 'single_step_execution',
                        duration: step_duration
                      })

        Rails.logger.error("StepExecutor: Unexpected error in execute_single_step for step #{step_id}: #{e.message}")
        nil
      end

      private

      # Execute steps concurrently with monitoring
      #
      # @param task [Tasker::Task] The task containing the steps
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @param viable_steps [Array<Tasker::WorkflowStep>] Steps ready for execution
      # @param task_handler [Object] The task handler instance
      # @return [Array<Tasker::WorkflowStep>] Successfully processed steps
      def execute_steps_concurrently_with_monitoring(task, sequence, viable_steps, task_handler)
        log_orchestration_event('concurrent_execution', :started,
                                task_id: task.task_id,
                                step_count: viable_steps.size,
                                max_concurrency: max_concurrent_steps)

        concurrent_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # Use the original concurrent execution logic without thread_pool
        results = execute_steps_concurrently(task, sequence, viable_steps, task_handler)

        concurrent_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - concurrent_start_time
        successful_count = results.count { |r| r&.status == Tasker::Constants::WorkflowStepStatuses::COMPLETE }

        log_performance_event('concurrent_execution', concurrent_duration,
                              task_id: task.task_id,
                              step_count: viable_steps.size,
                              successful_count: successful_count,
                              failure_count: results.size - successful_count)

        log_orchestration_event('concurrent_execution', :completed,
                                task_id: task.task_id,
                                step_count: viable_steps.size,
                                successful_count: successful_count,
                                duration_ms: (concurrent_duration * 1000).round(2))

        results
      end

      # Validate that the step and database connection are ready
      def validate_step_preconditions_with_logging(step)
        unless ActiveRecord::Base.connection.active?
          log_step_event(step, :validation_failed,
                         reason: 'database_connection_inactive',
                         step_status: step&.status)
          Rails.logger.error("StepExecutor: Database connection inactive for step #{step&.workflow_step_id}")
          return false
        end

        step = step.reload if step&.persisted?
        unless step
          log_structured(:error, 'Step validation failed',
                         reason: 'step_nil_or_not_persisted',
                         entity_type: 'step')
          Rails.logger.error('StepExecutor: Step is nil or not persisted')
          return false
        end

        log_step_event(step, :validation_passed,
                       step_status: step.status,
                       step_attempts: step.attempts)

        true
      rescue ActiveRecord::ConnectionNotEstablished, PG::ConnectionBad => e
        log_exception(e, context: {
                        step_id: step&.workflow_step_id,
                        operation: 'step_precondition_validation'
                      })
        Rails.logger.error("StepExecutor: Database connection error for step #{step&.workflow_step_id}: #{e.message}")
        false
      rescue StandardError => e
        log_exception(e, context: {
                        step_id: step&.workflow_step_id,
                        operation: 'step_precondition_validation'
                      })
        Rails.logger.error("StepExecutor: Unexpected error checking step #{step&.workflow_step_id}: #{e.message}")
        false
      end

      # Ensure step has an initial state, set to pending if blank
      def ensure_step_has_initial_state_with_logging(step) # rubocop:disable Naming/PredicateMethod
        current_state = step.state_machine.current_state
        return true if current_state.present?

        log_step_event(step, :state_initialization,
                       current_state: current_state,
                       target_state: Tasker::Constants::WorkflowStepStatuses::PENDING)

        Rails.logger.debug { "StepExecutor: Step #{step.workflow_step_id} has no state, setting to pending" }
        unless safe_transition_to(step, Tasker::Constants::WorkflowStepStatuses::PENDING)
          log_step_event(step, :state_initialization_failed,
                         current_state: current_state,
                         target_state: Tasker::Constants::WorkflowStepStatuses::PENDING)
          Rails.logger.error("StepExecutor: Failed to initialize step #{step.workflow_step_id} to pending state")
          return false
        end

        step.reload
        log_step_event(step, :state_initialized,
                       new_state: step.state_machine.current_state)
        true
      end

      # Check if step is in the correct state for execution
      def step_ready_for_execution_with_logging?(step)
        current_state = step.state_machine.current_state
        is_ready = current_state == Tasker::Constants::WorkflowStepStatuses::PENDING

        log_step_event(step, :readiness_check,
                       current_state: current_state,
                       is_ready: is_ready,
                       expected_state: Tasker::Constants::WorkflowStepStatuses::PENDING)

        return true if is_ready

        Rails.logger.debug do
          "StepExecutor: Skipping step #{step.workflow_step_id} - not pending (current: '#{current_state}')"
        end
        false
      end

      # Execute the main step workflow with monitoring: transition -> execute -> complete
      def execute_step_workflow_with_monitoring(task, sequence, step, task_handler, step_start_time)
        publish_execution_started_event(task, step)

        log_step_event(step, :workflow_starting,
                       task_id: task.task_id,
                       step_status: step.status,
                       elapsed_time_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - step_start_time) * 1000).round(2))

        # Execute step handler and handle both success and error cases
        begin
          # Transition to in_progress first - if this fails, it should be treated as an error
          transition_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          transition_step_to_in_progress!(step)
          transition_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - transition_start_time

          log_performance_event('step_state_transition', transition_duration,
                                task_id: task.task_id,
                                step_id: step.workflow_step_id,
                                from_state: Tasker::Constants::WorkflowStepStatuses::PENDING,
                                to_state: Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)

          # Execute the actual step handler with timing
          handler_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          execute_step_handler(task, sequence, step, task_handler)
          handler_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - handler_start_time

          log_performance_event('step_handler_execution', handler_duration,
                                task_id: task.task_id,
                                step_id: step.workflow_step_id,
                                step_name: step.name,
                                result: 'success')

          # Complete step execution with timing
          completion_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          result = complete_step_execution(task, step)
          completion_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - completion_start_time

          log_performance_event('step_completion', completion_duration,
                                task_id: task.task_id,
                                step_id: step.workflow_step_id,
                                final_status: result&.status)

          total_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - step_start_time
          log_step_event(step, :workflow_completed,
                         task_id: task.task_id,
                         final_status: result&.status,
                         total_duration_ms: (total_duration * 1000).round(2),
                         handler_duration_ms: (handler_duration * 1000).round(2))

          result
        rescue StandardError => e
          error_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - step_start_time

          log_step_event(step, :workflow_failed,
                         task_id: task.task_id,
                         error: e.message,
                         error_class: e.class.name,
                         duration_ms: (error_duration * 1000).round(2))

          log_performance_event('step_handler_execution', error_duration,
                                task_id: task.task_id,
                                step_id: step.workflow_step_id,
                                step_name: step.name,
                                result: 'failure',
                                error_class: e.class.name)

          # Store error data in step.results like legacy code
          store_step_error_data(step, e)

          # Complete error step execution with persistence (similar to complete_step_execution but for errors)
          error_completion_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          result = complete_error_step_execution(task, step)
          error_completion_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - error_completion_start_time

          log_performance_event('step_error_completion', error_completion_duration,
                                task_id: task.task_id,
                                step_id: step.workflow_step_id,
                                final_status: result&.status)

          nil
        end
      end

      # Publish event for step execution start
      def publish_execution_started_event(_task, step)
        # Use clean API for step execution start
        publish_step_started(step)
      end

      # Transition step to in_progress state (bang version that raises on failure)
      def transition_step_to_in_progress!(step)
        unless safe_transition_to(step, Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
          current_state = step.state_machine.current_state
          error_message = "Cannot transition step #{step.workflow_step_id} from '#{current_state}' to 'in_progress'. " \
                          'Check step dependencies and current state.'

          Rails.logger.warn("StepExecutor: #{error_message}")
          raise Tasker::ProceduralError, error_message
        end

        true
      end

      # Execute the actual step handler logic
      def execute_step_handler(task, sequence, step, task_handler)
        step_handler = task_handler.get_step_handler(step)
        step_handler.handle(task, sequence, step)
      end

      # Complete step execution and publish completion event
      #
      # This method ensures atomic completion by wrapping both the step save
      # and state transition in a database transaction. This is critical for
      # idempotency: if either operation fails, the step remains in "in_progress"
      # and can be safely retried without repeating the actual work.
      def complete_step_execution(_task, step)
        completed_step = nil

        # Update attempt tracking like legacy code (for consistency with error path)
        step.attempts ||= 0
        step.attempts += 1
        step.last_attempted_at = Time.zone.now

        # Use database transaction to ensure atomic completion
        ActiveRecord::Base.transaction do
          # STEP 1: Set completion flags for successful steps
          # Mark step as processed and not in_process (mirrors error path logic)
          step.processed = true
          step.in_process = false
          step.processed_at = Time.zone.now

          # STEP 2: Save the step results and flags
          # This persists the output of the work that has already been performed
          step.save!

          # STEP 3: Transition to complete state
          # This marks the step as done, but only if the save succeeded
          unless safe_transition_to(step, Tasker::Constants::WorkflowStepStatuses::COMPLETE)
            Rails.logger.error("StepExecutor: Failed to transition step #{step.workflow_step_id} to complete")
            # Raise exception to trigger transaction rollback
            raise ActiveRecord::Rollback, "Failed to transition step #{step.workflow_step_id} to complete state"
          end

          completed_step = step
        end

        # If we got here, both save and transition succeeded
        unless completed_step
          Rails.logger.error("StepExecutor: Step completion transaction rolled back for step #{step.workflow_step_id}")
          return nil
        end

        # Publish completion event outside transaction (for performance)
        publish_step_completed(
          step,
          attempt_number: step.attempts,
          execution_duration: step.processed_at&.-(step.updated_at)
        )

        Rails.logger.debug { "StepExecutor: Successfully completed step #{step.workflow_step_id}" }
        completed_step
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
        Rails.logger.error("StepExecutor: Failed to save step #{step.workflow_step_id}: #{e.message}")
        nil
      rescue StandardError => e
        Rails.logger.error("StepExecutor: Unexpected error completing step #{step.workflow_step_id}: #{e.message}")
        nil
      end

      # Store error data in step results (matching legacy pattern)
      def store_step_error_data(step, error)
        step.results ||= {}
        step.results = step.results.merge(
          error: error.to_s,
          backtrace: error.backtrace.join("\n"),
          error_class: error.class.name
        )

        # Update attempt tracking like legacy code
        step.attempts ||= 0
        step.attempts += 1
        step.last_attempted_at = Time.zone.now
      end

      # Complete error step execution with persistence and state transition
      #
      # This mirrors complete_step_execution but handles error state persistence.
      # Critical: We MUST save error steps to preserve error data and attempt tracking.
      def complete_error_step_execution(_task, step)
        completed_error_step = nil

        # Use database transaction to ensure atomic error completion
        ActiveRecord::Base.transaction do
          # STEP 1: Reset step flags for retry eligibility
          # Failed steps must be marked as not in_process and not processed
          # so they can be picked up for retry by the step readiness view
          step.in_process = false
          step.processed = false

          # STEP 2: Save the step with error data
          # This persists the error information and attempt tracking
          step.save!

          # STEP 3: Transition to error state
          # This marks the step as failed, but only if the save succeeded
          unless safe_transition_to(step, Tasker::Constants::WorkflowStepStatuses::ERROR)
            Rails.logger.error("StepExecutor: Failed to transition step #{step.workflow_step_id} to error")
            # Raise exception to trigger transaction rollback
            raise ActiveRecord::Rollback, "Failed to transition step #{step.workflow_step_id} to error state"
          end

          completed_error_step = step
        end

        # If we got here, both save and transition succeeded
        unless completed_error_step
          step_id = step.workflow_step_id
          Rails.logger.error("StepExecutor: Error step completion transaction rolled back for step #{step_id}")
          return nil
        end

        # Publish error event outside transaction (for performance)
        publish_step_failed(
          step,
          error_message: step.results['error'],
          error_class: step.results['error_class'],
          attempt_number: step.attempts,
          backtrace: step.results['backtrace']&.split("\n")&.first(10)
        )

        Rails.logger.debug { "StepExecutor: Successfully saved error step #{step.workflow_step_id}" }
        completed_error_step
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
        Rails.logger.error("StepExecutor: Failed to save error step #{step.workflow_step_id}: #{e.message}")
        nil
      rescue StandardError => e
        step_id = step.workflow_step_id
        Rails.logger.error("StepExecutor: Unexpected error completing error step #{step_id}: #{e.message}")
        nil
      end

      # Calculate optimal concurrency based on system health metrics
      #
      # Enhanced with ConnectionPoolIntelligence for Rails-aware connection management.
      # Falls back to legacy calculation if ConnectionPoolIntelligence is unavailable.
      #
      # @return [Integer] Calculated concurrency level
      def calculate_optimal_concurrency
        # Use enhanced ConnectionPoolIntelligence for Rails-aware calculation
        intelligence_concurrency = Tasker::Orchestration::ConnectionPoolIntelligence
                                   .intelligent_concurrency_for_step_executor

        # Combine with system health analysis for comprehensive optimization
        health_data = fetch_system_health_data
        if health_data
          # Apply additional system load considerations
          base_concurrency = calculate_base_concurrency(health_data)

          # Use the most conservative of both approaches for safety
          optimal_concurrency = [intelligence_concurrency, base_concurrency].min
        else
          # Use ConnectionPoolIntelligence recommendation when health data unavailable
          optimal_concurrency = intelligence_concurrency
        end

        # Ensure we stay within configured bounds
        optimal_concurrency.clamp(execution_config.min_concurrent_steps, execution_config.max_concurrent_steps_limit)
      rescue StandardError => e
        log_structured(:warn, 'Optimal concurrency calculation failed, using fallback', {
                         error_class: e.class.name,
                         error_message: e.message,
                         fallback_concurrency: execution_config.min_concurrent_steps
                       })
        execution_config.min_concurrent_steps
      end

      # Fetch system health data with error handling
      #
      # @return [HealthMetrics, nil] Health metrics or nil if unavailable
      def fetch_system_health_data
        Tasker::Functions::FunctionBasedSystemHealthCounts.call
      rescue StandardError => e
        Rails.logger.warn("StepExecutor: Failed to fetch system health data: #{e.message}")
        nil
      end

      # Fetch connection pool size with error handling
      #
      # @return [Integer, nil] Connection pool size or nil if unavailable
      def fetch_connection_pool_size
        ActiveRecord::Base.connection_pool&.size
      rescue StandardError => e
        Rails.logger.warn("StepExecutor: Failed to fetch connection pool size: #{e.message}")
        nil
      end

      # Calculate base concurrency from system health metrics
      #
      # @param health_data [HealthMetrics] System health metrics
      # @return [Integer] Base concurrency level
      def calculate_base_concurrency(health_data)
        # Calculate system load factor (0.0 to 1.0+)
        total_active_work = [health_data.in_progress_tasks + health_data.pending_tasks, 1].max
        load_factor = total_active_work.to_f / [health_data.total_tasks, 1].max

        # Calculate step processing load
        total_active_steps = [health_data.in_progress_steps + health_data.pending_steps, 1].max
        step_load_factor = total_active_steps.to_f / [health_data.total_steps, 1].max

        # Combine load factors (weighted toward step load)
        combined_load = (load_factor * 0.3) + (step_load_factor * 0.7)

        # Calculate concurrency based on load (inverse relationship)
        min_steps = execution_config.min_concurrent_steps
        max_steps = execution_config.max_concurrent_steps_limit

        if combined_load <= 0.3
          # Low load: Allow higher concurrency
          max_steps
        elsif combined_load <= 0.6
          # Moderate load: Medium concurrency
          (((max_steps - min_steps) * 0.6) + min_steps).round
        else
          # High load: Conservative concurrency
          min_steps + 1
        end
      rescue StandardError => e
        Rails.logger.warn("StepExecutor: Error calculating base concurrency: #{e.message}")
        execution_config.min_concurrent_steps
      end

      # Calculate connection-constrained concurrency
      #
      # @param health_data [HealthMetrics] System health metrics
      # @param pool_size [Integer] Connection pool size
      # @return [Integer] Connection-constrained concurrency level
      def calculate_connection_constrained_concurrency(health_data, pool_size)
        min_steps = execution_config.min_concurrent_steps
        max_steps = execution_config.max_concurrent_steps_limit

        return min_steps if pool_size <= 0

        # Get current connection usage
        active_connections = [health_data.active_connections, 0].max
        connection_utilization = active_connections.to_f / pool_size

        # Calculate available connections with safety margin
        available_connections = pool_size - active_connections
        safety_margin = [pool_size * 0.2, 2].max.round # 20% safety margin, minimum 2

        safe_available = available_connections - safety_margin

        # Don't allow concurrency that would exhaust connections
        if connection_utilization >= 0.9 || safe_available <= 2
          min_steps
        elsif connection_utilization >= 0.7
          [safe_available / 2, min_steps + 1].max
        else
          [safe_available, max_steps].min
        end
      rescue StandardError => e
        Rails.logger.warn("StepExecutor: Error calculating connection-constrained concurrency: #{e.message}")
        execution_config.min_concurrent_steps
      end

      # Execute steps concurrently using concurrent-ruby with enhanced memory management
      #
      # Enhanced with timeout protection, comprehensive future cleanup, and intelligent
      # garbage collection triggers to prevent memory leaks in long-running processes.
      #
      # @param task [Tasker::Task] The task containing the steps
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @param viable_steps [Array<Tasker::WorkflowStep>] Steps to execute
      # @param task_handler [Object] The task handler instance
      # @return [Array<Tasker::WorkflowStep>] Processed steps
      def execute_steps_concurrently(task, sequence, viable_steps, task_handler)
        results = []
        current_max_concurrency = max_concurrent_steps

        viable_steps.each_slice(current_max_concurrency) do |step_batch|
          futures = nil
          batch_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          begin
            # Create futures with connection pool management
            futures = step_batch.map do |step|
              Concurrent::Future.execute do
                # Ensure each future has its own database connection
                ActiveRecord::Base.connection_pool.with_connection do
                  execute_single_step(task, sequence, step, task_handler)
                end
              end
            end

            # Enhanced timeout protection with graceful degradation
            batch_results = collect_results_with_timeout(futures, step_batch.size, task.task_id)
            results.concat(batch_results.compact)
          rescue Concurrent::TimeoutError
            log_structured(:warn, 'Batch execution timeout',
                           task_id: task.task_id,
                           batch_size: step_batch.size,
                           timeout_seconds: calculate_batch_timeout(step_batch.size),
                           correlation_id: current_correlation_id)

            # Graceful degradation: collect any completed results
            completed_results = collect_completed_results(futures)
            results.concat(completed_results.compact)
          rescue StandardError => e
            log_structured(:error, 'Batch execution error',
                           task_id: task.task_id,
                           batch_size: step_batch.size,
                           error_class: e.class.name,
                           error_message: e.message,
                           correlation_id: current_correlation_id)

            # Attempt to collect any completed results before cleanup
            completed_results = collect_completed_results(futures) if futures
            results.concat(completed_results.compact) if completed_results
          ensure
            # ENHANCED: Comprehensive memory cleanup with intelligent GC
            cleanup_futures_with_memory_management(futures, step_batch.size, batch_start_time, task.task_id)
          end
        end

        results
      end

      # Get current correlation ID for logging context
      #
      # Ensures we always have a correlation ID for traceability. If the StepExecutor
      # doesn't have the StructuredLogging concern properly included, this will fail fast
      # rather than silently returning nil and masking workflow issues.
      #
      # @return [String] Current correlation ID (never nil)
      # @raise [RuntimeError] If StructuredLogging concern is not properly included
      def current_correlation_id
        unless respond_to?(:correlation_id, true)
          raise 'StepExecutor must include StructuredLogging concern for correlation ID support. ' \
                'This indicates a workflow or initialization issue.'
        end

        # The StructuredLogging concern automatically generates correlation IDs if none exist
        # This ensures we always have traceability without masking logical sequencing issues
        correlation_id
      end

      # Collect results with configurable timeout protection
      #
      # @param futures [Array<Concurrent::Future>] The futures to collect from
      # @param batch_size [Integer] Size of the batch for timeout calculation
      # @param task_id [String] Task ID for logging context
      # @return [Array] Results from completed futures
      def collect_results_with_timeout(futures, batch_size, task_id)
        timeout_seconds = calculate_batch_timeout(batch_size)

        log_structured(:debug, 'Collecting batch results with timeout',
                       task_id: task_id,
                       batch_size: batch_size,
                       timeout_seconds: timeout_seconds,
                       correlation_id: current_correlation_id)

        futures.map { |future| future.value(timeout_seconds) }
      rescue Concurrent::TimeoutError
        # Log timeout but let the caller handle graceful degradation
        log_structured(:warn, 'Future collection timeout',
                       task_id: task_id,
                       batch_size: batch_size,
                       timeout_seconds: timeout_seconds,
                       correlation_id: current_correlation_id)
        raise
      end

      # Calculate appropriate timeout based on batch size
      #
      # @param batch_size [Integer] Number of steps in the batch
      # @return [Numeric] Timeout in seconds
      def calculate_batch_timeout(batch_size)
        # Delegate to execution config for timeout calculation
        execution_config.calculate_batch_timeout(batch_size)
      end

      # Collect results from completed futures without waiting
      #
      # @param futures [Array<Concurrent::Future>] The futures to check
      # @return [Array] Results from completed futures only
      def collect_completed_results(futures)
        return [] unless futures

        completed_results = []
        futures.each do |future|
          if future.complete? && !future.rejected?
            completed_results << future.value
          elsif future.rejected?
            log_structured(:warn, 'Future rejected during collection',
                           reason: future.reason&.message,
                           correlation_id: current_correlation_id)
          end
        end

        completed_results
      rescue StandardError => e
        log_structured(:error, 'Error collecting completed results',
                       error_class: e.class.name,
                       error_message: e.message,
                       correlation_id: current_correlation_id)
        []
      end

      # Comprehensive future cleanup with memory management
      #
      # @param futures [Array<Concurrent::Future>] The futures to clean up
      # @param batch_size [Integer] Size of the processed batch
      # @param batch_start_time [Float] When the batch started processing
      # @param task_id [String] Task ID for logging context
      def cleanup_futures_with_memory_management(futures, batch_size, batch_start_time, task_id)
        return unless futures

        cleanup_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        begin
          # Step 1: Cancel any pending futures using domain-specific logic
          pending_count = 0
          futures.each do |future|
            analyzer = FutureStateAnalyzer.new(future)
            if analyzer.should_cancel?
              future.cancel
              pending_count += 1
            end
          end

          # Step 2: Wait briefly for executing futures to complete gracefully
          executing_count = 0
          futures.each do |future|
            analyzer = FutureStateAnalyzer.new(future)
            if analyzer.should_wait_for_completion?
              future.wait(execution_config.future_cleanup_wait_seconds)
              executing_count += 1
            end
          end

          # Step 3: Clear future references to prevent memory leaks
          futures.clear

          # Step 4: Intelligent GC trigger for memory pressure relief
          trigger_intelligent_gc(batch_size, task_id) if should_trigger_gc?(batch_size, batch_start_time)

          # Log cleanup metrics for observability
          cleanup_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - cleanup_start_time
          log_structured(:debug, 'Future cleanup completed',
                         task_id: task_id,
                         batch_size: batch_size,
                         pending_cancelled: pending_count,
                         executing_waited: executing_count,
                         cleanup_duration_ms: (cleanup_duration * 1000).round(2),
                         gc_triggered: should_trigger_gc?(batch_size, batch_start_time),
                         correlation_id: current_correlation_id)
        rescue StandardError => e
          log_structured(:error, 'Error during future cleanup',
                         task_id: task_id,
                         batch_size: batch_size,
                         error_class: e.class.name,
                         error_message: e.message,
                         correlation_id: current_correlation_id)
        end
      end

      # Determine if garbage collection should be triggered
      #
      # @param batch_size [Integer] Size of the processed batch
      # @param batch_start_time [Float] When the batch started processing
      # @return [Boolean] Whether GC should be triggered
      def should_trigger_gc?(batch_size, batch_start_time)
        batch_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - batch_start_time

        # Delegate to execution config for GC decision
        execution_config.should_trigger_gc?(batch_size, batch_duration)
      end

      # Trigger intelligent garbage collection with logging
      #
      # @param batch_size [Integer] Size of the batch that triggered GC
      # @param task_id [String] Task ID for logging context
      def trigger_intelligent_gc(batch_size, task_id)
        gc_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # Record memory stats before GC
        memory_before = GC.stat[:heap_live_slots] if GC.respond_to?(:stat)

        # Trigger GC
        GC.start

        # Record memory stats after GC
        memory_after = GC.stat[:heap_live_slots] if GC.respond_to?(:stat)
        gc_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - gc_start_time

        # Log GC metrics for memory monitoring
        log_structured(:info, 'Intelligent GC triggered',
                       task_id: task_id,
                       batch_size: batch_size,
                       gc_duration_ms: (gc_duration * 1000).round(2),
                       memory_before: memory_before,
                       memory_after: memory_after,
                       memory_freed: memory_before && memory_after ? (memory_before - memory_after) : nil,
                       correlation_id: current_correlation_id)
      rescue StandardError => e
        log_structured(:error, 'Error during intelligent GC',
                       task_id: task_id,
                       error_class: e.class.name,
                       error_message: e.message,
                       correlation_id: current_correlation_id)
      end
    end
  end
end
