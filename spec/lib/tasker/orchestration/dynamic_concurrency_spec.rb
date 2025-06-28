# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Dynamic Concurrency Optimization' do
  let(:step_executor) { Tasker::Orchestration::StepExecutor.new }
  let(:task) { create(:task, :with_workflow_steps, step_count: 6) }
  let(:task_handler) { double('TaskHandler') }
  let(:sequence) { double('StepSequence') }

  before do
    # Ensure clean state for each test
    step_executor.instance_variable_set(:@max_concurrent_steps, nil) if step_executor.instance_variable_defined?(:@max_concurrent_steps)
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
          double('ConnectionPool', size: 20)
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
          double('ConnectionPool', size: 20)
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
          double('ConnectionPool', size: 20)
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
          double('ConnectionPool', size: 20)
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
        double('ConnectionPool', size: 5)
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
        double('ConnectionPool', size: 100)
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
            total_tasks: -1,  # Invalid negative value
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
                       active_connections: 0,   # Invalid zero value
           max_connections: 0        # Invalid zero value
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
        double('ConnectionPool', size: 20)
      )

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      step_executor.max_concurrent_steps
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # Should complete in well under 100ms
      expect(end_time - start_time).to be < 0.1
    end
  end
end
