# frozen_string_literal: true

require 'swagger_helper'
require_relative '../../examples/test_authenticator'
require_relative '../../examples/custom_authorization_coordinator'

RSpec.describe 'Analytics API', type: :request do
  let!(:task_namespace) { create(:task_namespace, name: 'payments') }
  let!(:named_task) { create(:named_task, task_namespace: task_namespace, name: 'process_payment', version: '1.0.0') }
  let!(:task) { create(:task, named_task: named_task) }
  let!(:step) { create(:workflow_step, task: task) }

  around do |example|
    # Store original configuration
    original_config = Tasker::Configuration.configuration.dup

    # Configure basic telemetry settings for tests
    Tasker.configure do |config|
      config.telemetry do |telemetry|
        telemetry.metrics_enabled = true
        telemetry.metrics_auth_required = false
      end
      config.auth do |auth|
        auth.authentication_enabled = false
        auth.authorization_enabled = false
      end
    end

    example.run

    # Restore original configuration
    Tasker.instance_variable_set(:@configuration, original_config)
  end

  path '/tasker/analytics/performance' do
    get('performance analytics') do
      tags 'Analytics'
      description 'Get system-wide performance metrics and analytics. Authentication requirements depend on configuration.'
      operationId 'getPerformanceAnalytics'
      produces 'application/json'

      response(200, 'successful performance analytics') do
        before do
          # Mock telemetry backends for consistent test data
          trace_backend = Tasker::Telemetry::TraceBackend.instance
          log_backend = Tasker::Telemetry::LogBackend.instance
          event_router = Tasker::Telemetry::EventRouter.instance

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
        end

        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end

        run_test! do |response|
          expect(response).to have_http_status(:ok)
          expect(response.content_type).to eq('application/json; charset=utf-8')

          json_response = JSON.parse(response.body)

          # Verify main structure
          expect(json_response).to have_key('system_overview')
          expect(json_response).to have_key('performance_trends')
          expect(json_response).to have_key('telemetry_insights')
          expect(json_response).to have_key('generated_at')
          expect(json_response).to have_key('cache_info')

          # Verify system overview
          system_overview = json_response['system_overview']
          expect(system_overview).to have_key('active_tasks')
          expect(system_overview).to have_key('total_namespaces')
          expect(system_overview).to have_key('unique_task_types')
          expect(system_overview).to have_key('system_health_score')

          # Verify performance trends structure
          performance_trends = json_response['performance_trends']
          expect(performance_trends).to have_key('last_hour')
          expect(performance_trends).to have_key('last_4_hours')
          expect(performance_trends).to have_key('last_24_hours')

          # Verify each trend period has required metrics
          %w[last_hour last_4_hours last_24_hours].each do |period|
            trend = performance_trends[period]
            expect(trend).to have_key('task_throughput')
            expect(trend).to have_key('completion_rate')
            expect(trend).to have_key('error_rate')
            expect(trend).to have_key('avg_task_duration')
            expect(trend).to have_key('avg_step_duration')
            expect(trend).to have_key('step_throughput')
          end

          # Verify telemetry insights
          telemetry_insights = json_response['telemetry_insights']
          expect(telemetry_insights).to have_key('trace_stats')
          expect(telemetry_insights).to have_key('log_stats')
          expect(telemetry_insights).to have_key('event_router_stats')

          # Verify cache info
          cache_info = json_response['cache_info']
          expect(cache_info['cached']).to be true
          expect(cache_info['ttl_base']).to eq('90 seconds')
        end
      end

      response(503, 'analytics unavailable') do
        before do
          # Mock analytics service failure
          allow(Tasker::AnalyticsService).to receive(:calculate_performance_analytics).and_raise(StandardError, 'Analytics service unavailable')
        end

        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end

        run_test! do |response|
          expect(response).to have_http_status(:service_unavailable)

          json_response = JSON.parse(response.body)
          expect(json_response['error']).to eq('Performance analytics failed')
          expect(json_response['message']).to eq('Analytics service unavailable')
          expect(json_response).to have_key('timestamp')
        end
      end
    end
  end

  path '/tasker/analytics/bottlenecks' do
    get('bottleneck analysis') do
      tags 'Analytics'
      description 'Get bottleneck analysis scoped by task parameters. Authentication requirements depend on configuration.'
      operationId 'getBottleneckAnalysis'
      produces 'application/json'

      parameter name: :namespace, in: :query, type: :string, description: 'Filter by task namespace', required: false
      parameter name: :name, in: :query, type: :string, description: 'Filter by task name', required: false
      parameter name: :version, in: :query, type: :string, description: 'Filter by task version', required: false
      parameter name: :period, in: :query, type: :integer, description: 'Analysis period in hours (default: 24)', required: false

      response(200, 'successful bottleneck analysis') do
        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end

        run_test! do |response|
          expect(response).to have_http_status(:ok)
          expect(response.content_type).to eq('application/json; charset=utf-8')

          json_response = JSON.parse(response.body)

          # Verify main structure
          expect(json_response).to have_key('scope_summary')
          expect(json_response).to have_key('bottleneck_analysis')
          expect(json_response).to have_key('performance_distribution')
          expect(json_response).to have_key('recommendations')
          expect(json_response).to have_key('scope')
          expect(json_response).to have_key('analysis_period_hours')
          expect(json_response).to have_key('generated_at')
          expect(json_response).to have_key('cache_info')

          # Verify default values
          expect(json_response['analysis_period_hours']).to eq(24)
          expect(json_response['scope']).to eq({})

          # Verify bottleneck analysis structure
          bottleneck_analysis = json_response['bottleneck_analysis']
          expect(bottleneck_analysis).to have_key('slowest_tasks')
          expect(bottleneck_analysis).to have_key('slowest_steps')
          expect(bottleneck_analysis).to have_key('error_patterns')
          expect(bottleneck_analysis).to have_key('dependency_bottlenecks')

          # Verify scope summary
          scope_summary = json_response['scope_summary']
          expect(scope_summary).to have_key('total_tasks')
          expect(scope_summary).to have_key('unique_task_types')
          expect(scope_summary).to have_key('time_span_hours')

          # Verify recommendations is an array
          expect(json_response['recommendations']).to be_an(Array)

          # Verify cache info
          cache_info = json_response['cache_info']
          expect(cache_info['cached']).to be true
          expect(cache_info['ttl_base']).to eq('2 minutes')
        end
      end

      response(200, 'scoped bottleneck analysis') do
        let(:namespace) { 'payments' }
        let(:name) { 'process_payment' }
        let(:version) { '1.0.0' }
        let(:period) { 12 }

        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end

        run_test! do |response|
          expect(response).to have_http_status(:ok)

          json_response = JSON.parse(response.body)

          # Verify scoped parameters are applied
          expect(json_response['analysis_period_hours']).to eq(12)
          expect(json_response['scope']).to eq({
            'namespace' => 'payments',
            'name' => 'process_payment',
            'version' => '1.0.0'
          })
        end
      end

      response(503, 'bottleneck analysis unavailable') do
        before do
          # Mock bottleneck analysis failure
          allow(Tasker::AnalyticsService).to receive(:calculate_bottleneck_analytics).and_raise(StandardError, 'Database connection lost')
        end

        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end

        run_test! do |response|
          expect(response).to have_http_status(:service_unavailable)

          json_response = JSON.parse(response.body)
          expect(json_response['error']).to eq('Bottleneck analysis failed')
          expect(json_response['message']).to eq('Database connection lost')
          expect(json_response).to have_key('scope')
          expect(json_response).to have_key('timestamp')
        end
      end
    end
  end

  # Test caching behavior
  describe 'caching behavior' do
    it 'uses intelligent caching for performance endpoint' do
      cache_manager = instance_double(Tasker::Telemetry::IntelligentCacheManager)
      expect(Tasker::Telemetry::IntelligentCacheManager).to receive(:new).and_return(cache_manager)
      expect(cache_manager).to receive(:intelligent_fetch).with(
        match(/tasker:analytics:performance:/),
        base_ttl: 90.seconds
      ).and_yield.and_return({ test: 'cached_data', generated_at: Time.current })

      get '/tasker/analytics/performance'
      expect(response).to have_http_status(:ok)
    end

    it 'uses intelligent caching for bottlenecks endpoint' do
      cache_manager = instance_double(Tasker::Telemetry::IntelligentCacheManager)
      expect(Tasker::Telemetry::IntelligentCacheManager).to receive(:new).and_return(cache_manager)
      expect(cache_manager).to receive(:intelligent_fetch).with(
        match(/tasker:analytics:bottlenecks:/),
        base_ttl: 2.minutes
      ).and_yield.and_return({ test: 'cached_data', generated_at: Time.current })

      get '/tasker/analytics/bottlenecks'
      expect(response).to have_http_status(:ok)
    end
  end

  # Test authentication integration
  describe 'authentication integration' do
    context 'when metrics_auth_required is true' do
      around do |example|
        # Store original configuration
        original_config = Tasker::Configuration.configuration.dup

        # Configure with auth required
        Tasker.configure do |config|
          config.telemetry do |telemetry|
            telemetry.metrics_auth_required = true
          end
        end

        example.run

        # Restore original configuration
        Tasker.instance_variable_set(:@configuration, original_config)
      end

      it 'requires authentication for performance endpoint' do
        # Mock authentication system like other controller tests
        allow_any_instance_of(TestAuthenticator).to receive(:authenticate!).and_return(true)
        allow_any_instance_of(TestAuthenticator).to receive(:authenticated?).and_return(true)

        get '/tasker/analytics/performance'
        expect(response).to have_http_status(:ok)
      end

      it 'requires authentication for bottlenecks endpoint' do
        # Mock authentication system like other controller tests
        allow_any_instance_of(TestAuthenticator).to receive(:authenticate!).and_return(true)
        allow_any_instance_of(TestAuthenticator).to receive(:authenticated?).and_return(true)

        get '/tasker/analytics/bottlenecks'
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
