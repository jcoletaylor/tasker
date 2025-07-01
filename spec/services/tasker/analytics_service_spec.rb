# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::AnalyticsService, type: :service do
  let!(:task_namespace) { create(:task_namespace, name: 'payments') }
  let!(:named_task) { create(:named_task, task_namespace: task_namespace, name: 'process_payment', version: '1.0.0') }
  let!(:task) { create(:task, named_task: named_task) }
  let!(:workflow_step) { create(:workflow_step, task: task) }

  describe '.calculate_performance_analytics' do
    subject { described_class.calculate_performance_analytics }

    before do
      # Mock telemetry backends to avoid external dependencies
      trace_backend = instance_double(Tasker::Telemetry::TraceBackend)
      log_backend = instance_double(Tasker::Telemetry::LogBackend)
      event_router = instance_double(Tasker::Telemetry::EventRouter)

      allow(Tasker::Telemetry::TraceBackend).to receive(:instance).and_return(trace_backend)
      allow(Tasker::Telemetry::LogBackend).to receive(:instance).and_return(log_backend)
      allow(Tasker::Telemetry::EventRouter).to receive(:instance).and_return(event_router)

      allow(trace_backend).to receive(:stats).and_return({
        active_traces: 10,
        backend_uptime: 3600.0,
        instance_id: 'test-instance'
      })

      allow(log_backend).to receive(:stats).and_return({
        total_entries: 125,
        level_counts: { 'info' => 100, 'error' => 20, 'warn' => 5 },
        backend_uptime: 3600.0,
        instance_id: 'test-instance'
      })

      allow(event_router).to receive(:routing_stats).and_return({
        total_mappings: 56,
        active_mappings: 56,
        backend_distribution: { trace: 42, metrics: 56, logs: 35 }
      })

      # Mock the analytics metrics SQL function
      analytics_metrics = instance_double(
        Tasker::Functions::FunctionBasedAnalyticsMetrics::AnalyticsMetrics,
        active_tasks_count: 5,
        total_namespaces_count: 3,
        unique_task_types_count: 8,
        system_health_score: 0.95,
        task_throughput: 25,
        completion_rate: 85.0,
        error_rate: 5.0,
        avg_task_duration: 45.2,
        avg_step_duration: 12.5,
        step_throughput: 150
      )

      allow(Tasker::Functions::FunctionBasedAnalyticsMetrics).to receive(:call).and_return(analytics_metrics)
    end

    it 'returns a PerformanceAnalytics object' do
      expect(subject).to be_a(Tasker::AnalyticsService::PerformanceAnalytics)
    end

    it 'includes system overview data' do
      result = subject.to_h

      expect(result[:system_overview]).to include(
        active_tasks: 5,
        total_namespaces: 3,
        unique_task_types: 8,
        system_health_score: 0.95
      )
    end

    it 'includes performance trends for multiple periods' do
      result = subject.to_h

      expect(result[:performance_trends]).to have_key(:last_hour)
      expect(result[:performance_trends]).to have_key(:last_4_hours)
      expect(result[:performance_trends]).to have_key(:last_24_hours)

      # Each period should have performance metrics
      result[:performance_trends].each do |period, metrics|
        expect(metrics).to include(
          task_throughput: 25,
          completion_rate: 85.0,
          error_rate: 5.0,
          avg_task_duration: 45.2,
          avg_step_duration: 12.5,
          step_throughput: 150
        )
      end
    end

    it 'includes telemetry insights' do
      result = subject.to_h

      expect(result[:telemetry_insights]).to include(
        trace_stats: hash_including(active_traces: 10),
        log_stats: hash_including(total_entries: 125),
        event_router_stats: hash_including(total_mappings: 56)
      )
    end

    it 'includes generated timestamp' do
      expect(subject.generated_at).to be_within(1.second).of(Time.current)
    end
  end

  describe '.calculate_bottleneck_analytics' do
    let(:scope_params) { { namespace: 'payments', name: 'process_payment', version: '1.0.0' } }
    let(:period_hours) { 24 }

    subject { described_class.calculate_bottleneck_analytics(scope_params, period_hours) }

    before do
      # Mock SQL function calls for bottleneck analysis
      slowest_task = double(
        'SlowestTask',
        to_h: {
          task_id: task.task_id,
          duration_seconds: 120.5,
          task_name: 'process_payment',
          namespace_name: 'payments',
          step_count: 5,
          completed_steps: 4,
          error_steps: 1
        }
      )

      slowest_step = double(
        'SlowestStep',
        to_h: {
          workflow_step_id: workflow_step.workflow_step_id,
          duration_seconds: 45.2,
          step_name: 'validate_payment',
          task_name: 'process_payment',
          attempts: 2,
          retryable: true
        }
      )

      allow(Tasker::Functions::FunctionBasedSlowestTasks).to receive(:call).and_return([slowest_task])
      allow(Tasker::Functions::FunctionBasedSlowestSteps).to receive(:call).and_return([slowest_step])

      # Mock step readiness status for dependency analysis
      step_status = double(
        'StepStatus',
        current_state: 'pending',
        dependencies_satisfied: false,
        name: 'validate_payment'
      )

      allow(Tasker::Functions::FunctionBasedStepReadinessStatus).to receive(:for_tasks).and_return([step_status])
    end

    it 'returns a BottleneckAnalytics object' do
      expect(subject).to be_a(Tasker::AnalyticsService::BottleneckAnalytics)
    end

    it 'includes scope information' do
      result = subject.to_h

      expect(result[:scope]).to eq(scope_params)
      expect(result[:analysis_period_hours]).to eq(period_hours)
    end

    it 'includes scope summary' do
      result = subject.to_h

      expect(result[:scope_summary]).to include(
        total_tasks: be >= 0,
        unique_task_types: be >= 0,
        time_span_hours: 24.0
      )
    end

    it 'includes bottleneck analysis with slowest tasks and steps' do
      result = subject.to_h

      expect(result[:bottleneck_analysis]).to include(
        slowest_tasks: array_including(
          hash_including(
            task_id: task.task_id,
            duration_seconds: 120.5,
            task_name: 'process_payment'
          )
        ),
        slowest_steps: array_including(
          hash_including(
            workflow_step_id: workflow_step.workflow_step_id,
            duration_seconds: 45.2,
            step_name: 'validate_payment'
          )
        )
      )
    end

    it 'includes error patterns analysis' do
      result = subject.to_h

      expect(result[:bottleneck_analysis][:error_patterns]).to include(
        total_errors: be >= 0,
        recent_error_rate: be >= 0.0,
        common_error_types: be_an(Array),
        retry_success_rate: be >= 0.0
      )
    end

    it 'includes dependency bottlenecks analysis' do
      result = subject.to_h

      expect(result[:bottleneck_analysis][:dependency_bottlenecks]).to include(
        blocking_dependencies: be >= 0,
        avg_wait_time: be >= 0.0,
        most_blocked_steps: be_an(Array)
      )
    end

    it 'includes performance distribution' do
      result = subject.to_h

      expect(result[:performance_distribution]).to include(
        percentiles: hash_including(p50: be >= 0.0, p95: be >= 0.0, p99: be >= 0.0),
        distribution_buckets: be_an(Array)
      )
    end

    it 'includes recommendations' do
      result = subject.to_h

      expect(result[:recommendations]).to be_an(Array)
      expect(result[:recommendations].length).to be <= 5
    end

    context 'when scope parameters are empty' do
      let(:scope_params) { {} }

      it 'handles empty scope gracefully' do
        expect { subject }.not_to raise_error
        expect(subject.scope).to eq({})
      end
    end

    context 'when SQL functions fail' do
      before do
        allow(Tasker::Functions::FunctionBasedSlowestTasks).to receive(:call)
          .and_raise(StandardError, 'Database error')
        allow(Tasker::Functions::FunctionBasedSlowestSteps).to receive(:call)
          .and_raise(StandardError, 'Database error')
      end

      it 'gracefully handles failures with empty arrays' do
        result = subject.to_h

        expect(result[:bottleneck_analysis][:slowest_tasks]).to eq([])
        expect(result[:bottleneck_analysis][:slowest_steps]).to eq([])
      end
    end
  end

  describe 'private methods' do
    describe '.build_scoped_query' do
      let(:scope_params) { { namespace: 'payments', name: 'process_payment' } }
      let(:since_time) { 1.hour.ago }

      it 'builds properly scoped query' do
        query = described_class.send(:build_scoped_query, scope_params, since_time)

        expect(query).to be_a(ActiveRecord::Relation)
        # Verify the query includes our test task
        expect(query).to include(task)
      end

      it 'handles empty scope parameters' do
        query = described_class.send(:build_scoped_query, {}, since_time)

        expect(query).to be_a(ActiveRecord::Relation)
        expect(query).to include(task)
      end
    end

    describe '.calculate_retry_success_rate' do
      let(:scoped_query) { Tasker::Task.where(task_id: task.task_id) }

      before do
        # Create a workflow step with retry attempts
        create(:workflow_step, task: task, attempts: 2)
      end

      it 'calculates retry success rate correctly' do
        rate = described_class.send(:calculate_retry_success_rate, scoped_query)

        expect(rate).to be_a(Float)
        expect(rate).to be >= 0.0
        expect(rate).to be <= 100.0
      end

      it 'returns 0.0 for empty query' do
        empty_query = Tasker::Task.where(task_id: -1) # Non-existent task
        rate = described_class.send(:calculate_retry_success_rate, empty_query)

        expect(rate).to eq(0.0)
      end
    end

    describe '.find_most_blocked_step_names' do
      let(:task_ids) { [task.task_id] }

      before do
        # Mock step readiness status
        step_status = double(
          'StepStatus',
          current_state: 'pending',
          dependencies_satisfied: false,
          name: 'blocked_step'
        )

        allow(Tasker::Functions::FunctionBasedStepReadinessStatus).to receive(:for_tasks)
          .with(task_ids).and_return([step_status])
      end

      it 'returns array of blocked step names' do
        result = described_class.send(:find_most_blocked_step_names, task_ids)

        expect(result).to be_an(Array)
        expect(result).to include('blocked_step')
      end

      it 'returns fallback for empty task IDs' do
        result = described_class.send(:find_most_blocked_step_names, [])

        expect(result).to eq([])
      end

      it 'handles SQL function failures gracefully' do
        allow(Tasker::Functions::FunctionBasedStepReadinessStatus).to receive(:for_tasks)
          .and_raise(StandardError, 'Database error')

        result = described_class.send(:find_most_blocked_step_names, task_ids)

        expect(result).to eq(%w[data_validation external_api_calls])
      end
    end
  end

  describe 'data structures' do
    describe 'PerformanceAnalytics' do
      let(:analytics) do
        described_class::PerformanceAnalytics.new(
          system_overview: { active_tasks: 5 },
          performance_trends: { last_hour: { task_throughput: 10 } },
          telemetry_insights: { trace_stats: { active_traces: 3 } }
        )
      end

      it 'has proper attributes' do
        expect(analytics.system_overview).to eq({ active_tasks: 5 })
        expect(analytics.performance_trends).to eq({ last_hour: { task_throughput: 10 } })
        expect(analytics.telemetry_insights).to eq({ trace_stats: { active_traces: 3 } })
        expect(analytics.generated_at).to be_within(1.second).of(Time.current)
      end

      it 'converts to hash properly' do
        hash = analytics.to_h

        expect(hash).to include(
          system_overview: { active_tasks: 5 },
          performance_trends: { last_hour: { task_throughput: 10 } },
          telemetry_insights: { trace_stats: { active_traces: 3 } },
          generated_at: be_within(1.second).of(Time.current)
        )
      end
    end

    describe 'BottleneckAnalytics' do
      let(:analytics) do
        described_class::BottleneckAnalytics.new(
          scope_summary: { total_tasks: 10 },
          bottleneck_analysis: { slowest_tasks: [] },
          performance_distribution: { percentiles: {} },
          recommendations: ['Optimize queries'],
          scope: { namespace: 'test' },
          analysis_period_hours: 24
        )
      end

      it 'has proper attributes' do
        expect(analytics.scope).to eq({ namespace: 'test' })
        expect(analytics.analysis_period_hours).to eq(24)
        expect(analytics.recommendations).to eq(['Optimize queries'])
        expect(analytics.generated_at).to be_within(1.second).of(Time.current)
      end

      it 'converts to hash properly' do
        hash = analytics.to_h

        expect(hash).to include(
          scope_summary: { total_tasks: 10 },
          bottleneck_analysis: { slowest_tasks: [] },
          performance_distribution: { percentiles: {} },
          recommendations: ['Optimize queries'],
          scope: { namespace: 'test' },
          analysis_period_hours: 24,
          generated_at: be_within(1.second).of(Time.current)
        )
      end
    end
  end

  describe 'error handling' do
    context 'when analytics metrics function fails' do
      before do
        allow(Tasker::Functions::FunctionBasedAnalyticsMetrics).to receive(:call)
          .and_raise(StandardError, 'Database connection lost')
      end

      it 'raises the error for performance analytics' do
        expect { described_class.calculate_performance_analytics }.to raise_error(StandardError, 'Database connection lost')
      end
    end

    context 'when scope calculation fails' do
      let(:scope_params) { { namespace: 'invalid' } }

      it 'handles scope calculation errors gracefully' do
        result = described_class.calculate_bottleneck_analytics(scope_params, 24)

        expect(result.scope_summary).to include(
          total_tasks: 0,
          unique_task_types: 0,
          time_span_hours: 24.0
        )
      end
    end
  end
end