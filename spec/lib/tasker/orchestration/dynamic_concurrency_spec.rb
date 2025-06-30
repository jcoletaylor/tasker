# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Dynamic Concurrency Optimization' do
  let(:step_executor) { Tasker::Orchestration::StepExecutor.new }
  let(:task) { create(:task, :with_workflow_steps, step_count: 6) }
  let(:task_handler) { double('TaskHandler') }
  let(:sequence) { double('StepSequence') }

  before do
    # Ensure clean state for each test
    if step_executor.instance_variable_defined?(:@max_concurrent_steps)
      step_executor.instance_variable_set(:@max_concurrent_steps,
                                          nil)
    end
  end

  describe '#max_concurrent_steps' do
    context 'when system health is optimal' do
      before do
        allow(Tasker::Functions::FunctionBasedSystemHealthCounts).to receive(:call).and_return(
          Tasker::Functions::FunctionBasedSystemHealthCounts::HealthMetrics.new(
            total_tasks: 10,
            pending_tasks: 2,
            in_progress_tasks: 3,
            complete_tasks: 5,
            error_tasks: 0,
            cancelled_tasks: 0,
            total_steps: 40,
            pending_steps: 8,
            in_progress_steps: 12,
            complete_steps: 20,
            error_steps: 0,
            retryable_error_steps: 0,
            exhausted_retry_steps: 0,
            in_backoff_steps: 0,
            active_connections: 2,
            max_connections: 20
          )
        )

        allow(ActiveRecord::Base).to receive(:connection_pool).and_return(
          double('ConnectionPool', size: 20, stat: { size: 20, busy: 2, available: 18 })
        )
      end

      it 'calculates higher concurrency for low load systems' do
        expect(step_executor.max_concurrent_steps).to be > 3
        expect(step_executor.max_concurrent_steps).to be <= 12
      end

      it 'caches the calculation for performance' do
        # First call should calculate
        first_result = step_executor.max_concurrent_steps

        # Second call should use cached value (no additional health check)
        expect(Tasker::Functions::FunctionBasedSystemHealthCounts).not_to receive(:call)
        second_result = step_executor.max_concurrent_steps

        expect(second_result).to eq(first_result)
      end
    end

    context 'when system is under moderate load' do
      before do
        allow(Tasker::Functions::FunctionBasedSystemHealthCounts).to receive(:call).and_return(
          Tasker::Functions::FunctionBasedSystemHealthCounts::HealthMetrics.new(
            total_tasks: 50,
            pending_tasks: 15,
            in_progress_tasks: 20,
            complete_tasks: 15,
            error_tasks: 0,
            cancelled_tasks: 0,
            total_steps: 200,
            pending_steps: 60,
            in_progress_steps: 80,
            complete_steps: 60,
            error_steps: 0,
            retryable_error_steps: 0,
            exhausted_retry_steps: 0,
            in_backoff_steps: 0,
            active_connections: 12,
            max_connections: 20
          )
        )

        allow(ActiveRecord::Base).to receive(:connection_pool).and_return(
          double('ConnectionPool', size: 20, stat: { size: 20, busy: 2, available: 18 })
        )
      end

      it 'calculates moderate concurrency for moderate load' do
        result = step_executor.max_concurrent_steps
        expect(result).to be >= 3
        expect(result).to be <= 8
      end
    end

    context 'when system is under high load' do
      before do
        allow(Tasker::Functions::FunctionBasedSystemHealthCounts).to receive(:call).and_return(
          Tasker::Functions::FunctionBasedSystemHealthCounts::HealthMetrics.new(
            total_tasks: 100,
            pending_tasks: 30,
            in_progress_tasks: 50,
            complete_tasks: 20,
            error_tasks: 0,
            cancelled_tasks: 0,
            total_steps: 400,
            pending_steps: 120,
            in_progress_steps: 200,
            complete_steps: 80,
            error_steps: 0,
            retryable_error_steps: 0,
            exhausted_retry_steps: 0,
            in_backoff_steps: 0,
            active_connections: 18,
            max_connections: 20
          )
        )

        allow(ActiveRecord::Base).to receive(:connection_pool).and_return(
          double('ConnectionPool', size: 20, stat: { size: 20, busy: 2, available: 18 })
        )
      end

      it 'falls back to conservative concurrency for high load' do
        result = step_executor.max_concurrent_steps
        expect(result).to be >= 3
        expect(result).to be <= 5
      end
    end

    context 'when database connections are exhausted' do
      before do
        allow(Tasker::Functions::FunctionBasedSystemHealthCounts).to receive(:call).and_return(
          Tasker::Functions::FunctionBasedSystemHealthCounts::HealthMetrics.new(
            total_tasks: 10,
            pending_tasks: 2,
            in_progress_tasks: 3,
            complete_tasks: 5,
            error_tasks: 0,
            cancelled_tasks: 0,
            total_steps: 40,
            pending_steps: 8,
            in_progress_steps: 12,
            complete_steps: 20,
            error_steps: 0,
            retryable_error_steps: 0,
            exhausted_retry_steps: 0,
            in_backoff_steps: 0,
            active_connections: 19,
            max_connections: 20
          )
        )

        allow(ActiveRecord::Base).to receive(:connection_pool).and_return(
          double('ConnectionPool', size: 5, stat: { size: 5, busy: 4, available: 1 })
        )
      end

      it 'uses minimum safe concurrency when connections are nearly exhausted' do
        result = step_executor.max_concurrent_steps
        expect(result).to eq(3)
      end
    end

    context 'when health check fails' do
      before do
        allow(Tasker::Functions::FunctionBasedSystemHealthCounts).to receive(:call)
          .and_raise(ActiveRecord::StatementInvalid.new('Connection failed'))
      end

      it 'falls back to safe default concurrency' do
        result = step_executor.max_concurrent_steps
        expect(result).to eq(3)
      end
    end
  end

  describe '#calculate_optimal_concurrency' do
    it 'respects minimum concurrency bounds' do
      # Mock extreme low resource scenario
      allow(Tasker::Functions::FunctionBasedSystemHealthCounts).to receive(:call).and_return(
        Tasker::Functions::FunctionBasedSystemHealthCounts::HealthMetrics.new(
          total_tasks: 1,
          pending_tasks: 0,
          in_progress_tasks: 1,
          complete_tasks: 0,
          error_tasks: 0,
          cancelled_tasks: 0,
          total_steps: 4,
          pending_steps: 0,
          in_progress_steps: 4,
          complete_steps: 0,
          error_steps: 0,
          retryable_error_steps: 0,
          exhausted_retry_steps: 0,
          in_backoff_steps: 0,
          active_connections: 1,
          max_connections: 5
        )
      )

      allow(ActiveRecord::Base).to receive(:connection_pool).and_return(
        double('ConnectionPool', size: 5, stat: { size: 5, busy: 4, available: 1 })
      )

      # Even with very low resources, should never go below 3
      result = step_executor.max_concurrent_steps
      expect(result).to be >= 3
    end

    it 'respects maximum concurrency bounds' do
      # Mock extremely high resource scenario
      allow(Tasker::Functions::FunctionBasedSystemHealthCounts).to receive(:call).and_return(
        Tasker::Functions::FunctionBasedSystemHealthCounts::HealthMetrics.new(
          total_tasks: 1,
          pending_tasks: 0,
          in_progress_tasks: 1,
          complete_tasks: 0,
          error_tasks: 0,
          cancelled_tasks: 0,
          total_steps: 4,
          pending_steps: 0,
          in_progress_steps: 4,
          complete_steps: 0,
          error_steps: 0,
          retryable_error_steps: 0,
          exhausted_retry_steps: 0,
          in_backoff_steps: 0,
          active_connections: 1,
          max_connections: 100
        )
      )

      allow(ActiveRecord::Base).to receive(:connection_pool).and_return(
        double('ConnectionPool', size: 100, stat: { size: 100, busy: 10, available: 90 })
      )

      # Even with very high resources, should never exceed reasonable maximum
      result = step_executor.max_concurrent_steps
      expect(result).to be <= 12
    end
  end

  describe 'integration with concurrent execution' do
    let(:viable_steps) { task.workflow_steps.limit(6) }

    before do
      allow(task_handler).to receive(:get_step_handler).and_return(
        double('StepHandler', handle: double('Result'))
      )

      # Mock step execution to avoid complex setup
      allow(step_executor).to receive(:execute_single_step).and_return(
        double('Step', workflow_step_id: 1, status: 'complete')
      )
    end

    context 'when dynamic concurrency allows higher throughput' do
      before do
        # Mock high-resource scenario
        allow(step_executor).to receive(:max_concurrent_steps).and_return(6)
      end

      it 'processes more steps concurrently than the old static limit' do
        # With 6 steps and max_concurrent_steps = 6, should process all in one batch
        expect(step_executor).to receive(:execute_single_step).exactly(6).times

        result = step_executor.send(:execute_steps_concurrently, task, sequence, viable_steps, task_handler)
        expect(result.size).to eq(6)
      end
    end

    context 'when dynamic concurrency requires conservative approach' do
      before do
        # Mock resource-constrained scenario
        allow(step_executor).to receive(:max_concurrent_steps).and_return(3)
      end

      it 'processes steps in smaller batches when resources are constrained' do
        # With 6 steps and max_concurrent_steps = 3, should process in 2 batches
        expect(step_executor).to receive(:execute_single_step).exactly(6).times

        result = step_executor.send(:execute_steps_concurrently, task, sequence, viable_steps, task_handler)
        expect(result.size).to eq(6)
      end
    end
  end

  describe 'error handling and resilience' do
    context 'when connection pool is nil' do
      before do
        allow(ActiveRecord::Base).to receive(:connection_pool).and_return(nil)
      end

      it 'falls back to safe default' do
        result = step_executor.max_concurrent_steps
        expect(result).to eq(3)
      end
    end

    context 'when health metrics contain unexpected values' do
      before do
        allow(Tasker::Functions::FunctionBasedSystemHealthCounts).to receive(:call).and_return(
          Tasker::Functions::FunctionBasedSystemHealthCounts::HealthMetrics.new(
            total_tasks: -1, # Invalid negative value
            pending_tasks: 0,
            in_progress_tasks: 0,
            complete_tasks: 0,
            error_tasks: 0,
            cancelled_tasks: 0,
            total_steps: 0,
            pending_steps: 0,
            in_progress_steps: 0,
            complete_steps: 0,
            error_steps: 0,
            retryable_error_steps: 0,
            exhausted_retry_steps: 0,
            in_backoff_steps: 0,
            active_connections: 0, # Invalid zero value
            max_connections: 0 # Invalid zero value
          )
        )
      end

      it 'handles invalid health data gracefully' do
        result = step_executor.max_concurrent_steps
        expect(result).to eq(3)
      end
    end
  end

  describe 'performance characteristics' do
    it 'completes calculation within reasonable time' do
      # Mock normal health check
      allow(Tasker::Functions::FunctionBasedSystemHealthCounts).to receive(:call).and_return(
        Tasker::Functions::FunctionBasedSystemHealthCounts::HealthMetrics.new(
          total_tasks: 10,
          pending_tasks: 2,
          in_progress_tasks: 3,
          complete_tasks: 5,
          error_tasks: 0,
          cancelled_tasks: 0,
          total_steps: 40,
          pending_steps: 8,
          in_progress_steps: 12,
          complete_steps: 20,
          error_steps: 0,
          retryable_error_steps: 0,
          exhausted_retry_steps: 0,
          in_backoff_steps: 0,
          active_connections: 5,
          max_connections: 20
        )
      )

      allow(ActiveRecord::Base).to receive(:connection_pool).and_return(
        double('ConnectionPool', size: 20, stat: { size: 20, busy: 5, available: 15 })
      )

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      step_executor.max_concurrent_steps
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # Should complete in well under 100ms
      expect(end_time - start_time).to be < 0.1
    end
  end

  describe 'enhanced memory management' do
    let(:step_executor) { Tasker::Orchestration::StepExecutor.new }
    let(:task) { create(:task) }
    let(:task_handler) { double('TaskHandler') }
    let(:sequence) { double('sequence') }

    before do
      allow(sequence).to receive(:any_method).and_return(true)
      allow(task_handler).to receive(:get_step_handler).and_return(double('step_handler'))
    end

    describe '#collect_results_with_timeout' do
      it 'collects results within timeout successfully' do
        futures = [
          double('future1', value: 'result1'),
          double('future2', value: 'result2')
        ]

        expect(step_executor.send(:collect_results_with_timeout, futures, 2, task.task_id))
          .to eq(%w[result1 result2])
      end

      it 'handles timeout gracefully and re-raises TimeoutError' do
        timeout_future = double('timeout_future')
        allow(timeout_future).to receive(:value).and_raise(Concurrent::TimeoutError)

        expect do
          step_executor.send(:collect_results_with_timeout, [timeout_future], 1, task.task_id)
        end.to raise_error(Concurrent::TimeoutError)
      end

      it 'logs timeout with proper context' do
        timeout_future = double('timeout_future')
        allow(timeout_future).to receive(:value).and_raise(Concurrent::TimeoutError)

        expect(step_executor).to receive(:log_structured).with(
          :debug, 'Collecting batch results with timeout', hash_including(
                                                             task_id: task.task_id,
                                                             batch_size: 1
                                                           )
        )

        expect(step_executor).to receive(:log_structured).with(
          :warn, 'Future collection timeout', hash_including(
                                                task_id: task.task_id,
                                                batch_size: 1
                                              )
        )

        expect do
          step_executor.send(:collect_results_with_timeout, [timeout_future], 1, task.task_id)
        end.to raise_error(Concurrent::TimeoutError)
      end
    end

    describe '#calculate_batch_timeout' do
      it 'calculates timeout based on batch size' do
        # Base (30s) + (2 steps * 5s) = 40s
        expect(step_executor.send(:calculate_batch_timeout, 2)).to eq(40.seconds)
      end

      it 'respects maximum timeout cap' do
        # Large batch should be capped at MAX_BATCH_TIMEOUT_SECONDS
        large_batch_size = 100
        expect(step_executor.send(:calculate_batch_timeout, large_batch_size))
          .to eq(120.seconds) # MAX_BATCH_TIMEOUT_SECONDS
      end

      it 'handles minimum batch size correctly' do
        # Base (30s) + (1 step * 5s) = 35s
        expect(step_executor.send(:calculate_batch_timeout, 1)).to eq(35.seconds)
      end
    end

    describe '#collect_completed_results' do
      it 'collects results from completed futures only' do
        completed_future = double('completed', complete?: true, rejected?: false, value: 'result1')
        pending_future = double('pending', complete?: false, rejected?: false)
        rejected_future = double('rejected', complete?: false, rejected?: true, reason: StandardError.new('test error'))

        futures = [completed_future, pending_future, rejected_future]

        expect(step_executor.send(:collect_completed_results, futures)).to eq(['result1'])
      end

      it 'handles nil futures gracefully' do
        expect(step_executor.send(:collect_completed_results, nil)).to eq([])
      end

      it 'logs rejected futures with reason' do
        rejected_future = double('rejected',
                                 complete?: false,
                                 rejected?: true,
                                 reason: StandardError.new('test rejection'))

        expect(step_executor).to receive(:log_structured).with(
          :warn, 'Future rejected during collection', hash_including(
                                                        reason: 'test rejection'
                                                      )
        )

        step_executor.send(:collect_completed_results, [rejected_future])
      end

      it 'handles errors during collection gracefully' do
        error_future = double('error_future')
        allow(error_future).to receive(:complete?).and_raise(StandardError.new('collection error'))

        expect(step_executor).to receive(:log_structured).with(
          :error, 'Error collecting completed results', hash_including(
                                                          error_class: 'StandardError',
                                                          error_message: 'collection error'
                                                        )
        )

        result = step_executor.send(:collect_completed_results, [error_future])
        expect(result).to eq([])
      end
    end

    describe '#cleanup_futures_with_memory_management' do
      let(:batch_start_time) { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

      it 'cancels pending futures and waits for executing ones' do
        pending_future = double('pending', pending?: true, incomplete?: true, unscheduled?: false)
        executing_future = double('executing', pending?: false, incomplete?: true, unscheduled?: false)
        completed_future = double('completed', pending?: false, incomplete?: false, unscheduled?: false)
        unscheduled_future = double('unscheduled', pending?: false, incomplete?: true, unscheduled?: true)

        futures = [pending_future, executing_future, completed_future, unscheduled_future]

        expect(pending_future).to receive(:cancel)
        expect(executing_future).to receive(:wait).with(1.second)
        # completed_future and unscheduled_future should not be touched
        expect(futures).to receive(:clear)

        step_executor.send(:cleanup_futures_with_memory_management,
                           futures, 4, batch_start_time, task.task_id)
      end

      it 'handles nil futures gracefully' do
        expect do
          step_executor.send(:cleanup_futures_with_memory_management,
                             nil, 3, batch_start_time, task.task_id)
        end.not_to raise_error
      end

      it 'logs cleanup metrics' do
        futures = []
        allow(futures).to receive(:clear)

        expect(step_executor).to receive(:log_structured).with(
          :debug, 'Future cleanup completed', hash_including(
                                                task_id: task.task_id,
                                                batch_size: 3,
                                                pending_cancelled: 0,
                                                executing_waited: 0
                                              )
        )

        step_executor.send(:cleanup_futures_with_memory_management,
                           futures, 3, batch_start_time, task.task_id)
      end

      it 'handles cleanup errors gracefully' do
        error_future = double('error_future')
        allow(error_future).to receive(:pending?).and_raise(StandardError.new('cleanup error'))

        futures = [error_future]

        expect(step_executor).to receive(:log_structured).with(
          :error, 'Error during future cleanup', hash_including(
                                                   task_id: task.task_id,
                                                   error_class: 'StandardError',
                                                   error_message: 'cleanup error'
                                                 )
        )

        step_executor.send(:cleanup_futures_with_memory_management,
                           futures, 3, batch_start_time, task.task_id)
      end
    end

    describe '#should_trigger_gc?' do
      let(:batch_start_time) { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

      it 'triggers GC for large batches' do
        large_batch_size = 6 # GC_TRIGGER_BATCH_SIZE_THRESHOLD
        expect(step_executor.send(:should_trigger_gc?, large_batch_size, batch_start_time)).to be true
      end

      it 'triggers GC for long-running batches' do
        old_batch_start = batch_start_time - 31.seconds # > GC_TRIGGER_DURATION_THRESHOLD
        expect(step_executor.send(:should_trigger_gc?, 3, old_batch_start)).to be true
      end

      it 'does not trigger GC for small, fast batches' do
        small_batch_size = 3
        expect(step_executor.send(:should_trigger_gc?, small_batch_size, batch_start_time)).to be false
      end
    end

    describe '#trigger_intelligent_gc' do
      it 'triggers GC and logs metrics' do
        expect(GC).to receive(:start)
        allow(GC).to receive(:stat).and_return({ heap_live_slots: 1000 }, { heap_live_slots: 800 })

        expect(step_executor).to receive(:log_structured).with(
          :info, 'Intelligent GC triggered', hash_including(
                                               task_id: task.task_id,
                                               batch_size: 6,
                                               memory_before: 1000,
                                               memory_after: 800,
                                               memory_freed: 200
                                             )
        )

        step_executor.send(:trigger_intelligent_gc, 6, task.task_id)
      end

      it 'handles GC errors gracefully' do
        allow(GC).to receive(:start).and_raise(StandardError.new('GC error'))

        expect(step_executor).to receive(:log_structured).with(
          :error, 'Error during intelligent GC', hash_including(
                                                   task_id: task.task_id,
                                                   error_class: 'StandardError',
                                                   error_message: 'GC error'
                                                 )
        )

        step_executor.send(:trigger_intelligent_gc, 6, task.task_id)
      end

      it 'handles missing GC.stat gracefully' do
        # Mock GC to not respond to stat but allow start and respond_to? calls
        allow(GC).to receive(:respond_to?).with(:stat).and_return(false)
        allow(GC).to receive(:respond_to?).with(:start, true).and_return(true)
        allow(GC).to receive(:start).and_return(nil)

        expect do
          step_executor.send(:trigger_intelligent_gc, 6, 'test_task_123')
        end.not_to raise_error
      end
    end

    describe 'enhanced concurrent execution with memory management' do
      let(:viable_steps) { create_list(:workflow_step, 3, task: task) }

      before do
        allow(step_executor).to receive_messages(max_concurrent_steps: 3, execute_single_step: viable_steps.first)
      end

      it 'handles timeout errors gracefully' do
        # Create mock futures that behave like real Concurrent::Future objects
        timeout_future = double('timeout_future')
        allow(timeout_future).to receive_messages(
          pending?: false,
          incomplete?: true,
          unscheduled?: false,
          rejected?: false,
          complete?: false # Add missing complete? method
        )
        allow(timeout_future).to receive(:cancel)
        allow(timeout_future).to receive(:wait)

        # Mock the step executor to use our mock futures
        allow(step_executor).to receive(:execute_steps_concurrently).and_call_original

        # Create mock steps that will cause a timeout
        steps = [double('step1'), double('step2'), double('step3')]

        # Mock Concurrent::Future.execute to return our mock future
        allow(Concurrent::Future).to receive(:execute).and_return(timeout_future)

        # Allow the timeout to be raised
        allow(timeout_future).to receive(:value).and_raise(Concurrent::TimeoutError)

        # Expect the method to handle timeout gracefully
        expect do
          step_executor.send(:execute_steps_concurrently, task, sequence, steps, task_handler)
        end.not_to raise_error
      end

      it 'handles general errors gracefully' do
        # Create mock futures that behave like real Concurrent::Future objects
        error_future = double('error_future')
        allow(error_future).to receive_messages(
          pending?: false,
          incomplete?: true,
          unscheduled?: false,
          rejected?: false,
          complete?: false # Add missing complete? method
        )
        allow(error_future).to receive(:cancel)
        allow(error_future).to receive(:wait)

        # Create mock steps that will cause an error
        steps = [double('step1'), double('step2'), double('step3')]

        # Mock Concurrent::Future.execute to return our mock future
        allow(Concurrent::Future).to receive(:execute).and_return(error_future)

        # Allow a general error to be raised
        allow(error_future).to receive(:value).and_raise(StandardError.new('test error'))

        # Expect the method to handle errors gracefully
        expect do
          step_executor.send(:execute_steps_concurrently, task, sequence, steps, task_handler)
        end.not_to raise_error
      end

      it 'always calls cleanup regardless of success or failure' do
        allow(Concurrent::Future).to receive(:execute).and_return(double('future', value: viable_steps.first))

        expect(step_executor).to receive(:cleanup_futures_with_memory_management)

        step_executor.send(:execute_steps_concurrently, task, sequence, viable_steps, task_handler)
      end
    end

    describe '#current_correlation_id' do
      it 'returns a correlation ID when StructuredLogging is properly included' do
        correlation_id = step_executor.send(:current_correlation_id)
        expect(correlation_id).to be_a(String)
        expect(correlation_id).not_to be_empty
        expect(correlation_id).to match(/\Atsk_\w+_\w+\z/) # Matches Tasker's correlation ID format
      end

      it 'returns the same correlation ID within the same thread context' do
        first_call = step_executor.send(:current_correlation_id)
        second_call = step_executor.send(:current_correlation_id)
        expect(first_call).to eq(second_call)
      end

      it 'generates a new correlation ID if none exists in thread context' do
        # Clear any existing correlation ID
        Thread.current[:tasker_correlation_id] = nil

        correlation_id = step_executor.send(:current_correlation_id)
        expect(correlation_id).to be_a(String)
        expect(correlation_id).not_to be_empty
      end

      it 'would fail fast if StructuredLogging concern was not included' do
        # Create a mock class without StructuredLogging
        mock_class = Class.new do
          def current_correlation_id
            unless respond_to?(:correlation_id, true)
              raise 'StepExecutor must include StructuredLogging concern for correlation ID support. ' \
                    'This indicates a workflow or initialization issue.'
            end
            correlation_id
          end
        end

        mock_instance = mock_class.new
        expect do
          mock_instance.current_correlation_id
        end.to raise_error(/StepExecutor must include StructuredLogging concern/)
      end
    end
  end
end
