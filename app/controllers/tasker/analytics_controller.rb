# frozen_string_literal: true

require_dependency 'tasker/application_controller'

module Tasker
  # Analytics controller providing performance and bottleneck analysis endpoints.
  #
  # This controller provides analytics endpoints:
  # - `/analytics/performance` - System-wide performance metrics with caching
  # - `/analytics/bottlenecks` - Bottleneck analysis scoped by task/version/namespace
  #
  # All endpoints use the authorization system with appropriate permissions.
  # If authorization is disabled, access is allowed. If enabled, users need
  # the corresponding analytics permissions.
  class AnalyticsController < ApplicationController
    # Set cache headers to prevent default caching (we use intelligent caching)
    before_action :set_cache_headers

    # Initialize intelligent cache for expensive analytics operations
    before_action :set_intelligent_cache

    # Performance analytics endpoint with intelligent caching
    # Provides system-wide performance metrics and trends
    #
    # @return [JSON] Performance metrics and analytics
    def performance
      cache_key = "tasker:analytics:performance:#{performance_cache_version}"

      cached_result = @intelligent_cache.intelligent_fetch(cache_key, base_ttl: 90.seconds) do
        performance_data = calculate_performance_analytics

        {
          **performance_data,
          generated_at: Time.current,
          cache_info: {
            cached: true,
            cache_key: cache_key,
            ttl_base: '90 seconds'
          }
        }
      end

      render json: cached_result, status: :ok
    rescue StandardError => e
      render json: {
        error: 'Performance analytics failed',
        message: e.message,
        timestamp: Time.current.iso8601
      }, status: :service_unavailable
    end

    # Bottleneck analysis endpoint scoped by task parameters
    # Provides bottleneck analysis for specific task contexts
    #
    # Query parameters:
    # - namespace: Filter by task namespace (optional)
    # - name: Filter by task name (optional)
    # - version: Filter by task version (optional)
    # - period: Analysis period in hours (default: 24)
    #
    # @return [JSON] Bottleneck analysis for specified scope
    def bottlenecks
      # Extract and validate scope parameters
      scope_params = extract_scope_parameters
      analysis_period = params[:period]&.to_i || 24

      # Generate cache key based on scope and period
      cache_key = "tasker:analytics:bottlenecks:#{bottlenecks_cache_version(scope_params, analysis_period)}"

      cached_result = @intelligent_cache.intelligent_fetch(cache_key, base_ttl: 2.minutes) do
        bottleneck_data = calculate_bottleneck_analytics(scope_params, analysis_period)

        {
          **bottleneck_data,
          scope: scope_params,
          analysis_period_hours: analysis_period,
          generated_at: Time.current,
          cache_info: {
            cached: true,
            cache_key: cache_key,
            ttl_base: '2 minutes'
          }
        }
      end

      render json: cached_result, status: :ok
    rescue StandardError => e
      render json: {
        error: 'Bottleneck analysis failed',
        message: e.message,
        scope: extract_scope_parameters,
        timestamp: Time.current.iso8601
      }, status: :service_unavailable
    end

    private

    def set_intelligent_cache
      @intelligent_cache = Tasker::Telemetry::IntelligentCacheManager.new
    end

    # Extract and validate scope parameters for bottleneck analysis
    #
    # @return [Hash] Validated scope parameters
    def extract_scope_parameters
      scope = {}
      scope[:namespace] = params[:namespace] if params[:namespace].present?
      scope[:name] = params[:name] if params[:name].present?
      scope[:version] = params[:version] if params[:version].present?
      scope
    end

    # Generate cache version for performance analytics
    #
    # @return [String] Cache version that changes when system state changes
    def performance_cache_version
      current_10min_interval = "#{Time.current.strftime('%Y%m%d%H%M')[0..-2]}0" # Round to 10-minute intervals

      # Include recent activity indicators for cache invalidation
      recent_tasks = Task.created_since(30.minutes.ago).count
      recent_completions = WorkflowStep.completed_since(30.minutes.ago).count

      "v1:#{current_10min_interval}:#{recent_tasks}:#{recent_completions}"
    end

    # Generate cache version for bottleneck analysis
    #
    # @param scope_params [Hash] Scope parameters for the analysis
    # @param period [Integer] Analysis period in hours
    # @return [String] Cache version for bottleneck analysis
    def bottlenecks_cache_version(scope_params, period)
      current_10min_interval = "#{Time.current.strftime('%Y%m%d%H%M')[0..-2]}0" # Round to 10-minute intervals
      scope_hash = scope_params.values.join('_').presence || 'all'

      "v1:#{current_10min_interval}:#{scope_hash}:#{period}h"
    end

    # Calculate comprehensive performance analytics
    #
    # @return [Hash] Performance analytics data
    def calculate_performance_analytics
      analysis_periods = {
        last_hour: 1.hour.ago,
        last_4_hours: 4.hours.ago,
        last_24_hours: 24.hours.ago
      }

      analytics = {
        system_overview: calculate_system_overview,
        performance_trends: {},
        telemetry_insights: calculate_telemetry_insights
      }

      # Calculate trends for each time period
      analysis_periods.each do |period_name, since_time|
        analytics[:performance_trends][period_name] = calculate_period_performance(since_time)
      end

      analytics
    end

    # Calculate system overview metrics using ActiveRecord queries
    #
    # @return [Hash] System overview data
    def calculate_system_overview
      # Use ActiveRecord queries and scopes for reliable results
      {
        active_tasks: Task.active.count,
        total_namespaces: Tasker::TaskNamespace.count,
        unique_task_types: Task.unique_task_types_count,
        system_health_score: calculate_health_score_from_metrics
      }
    end

    # Calculate performance metrics for a specific period using ActiveRecord
    #
    # @param since_time [Time] Start time for analysis
    # @return [Hash] Performance metrics for the period
    def calculate_period_performance(since_time)
      # Use ActiveRecord queries for reliable results
      total_tasks = Task.created_since(since_time).count
      completed_tasks = Task.completed_since(since_time).count
      failed_tasks = Task.failed_since(since_time).count
      total_steps = WorkflowStep.for_tasks_since(since_time).count

      {
        task_throughput: total_tasks,
        completion_rate: total_tasks.positive? ? (completed_tasks.to_f / total_tasks * 100).round(2) : 0.0,
        error_rate: total_tasks.positive? ? (failed_tasks.to_f / total_tasks * 100).round(2) : 0.0,
        avg_task_duration: calculate_avg_task_duration(since_time),
        avg_step_duration: calculate_avg_step_duration(since_time),
        step_throughput: total_steps
      }
    end

    # Calculate telemetry insights from trace and log backends
    #
    # @return [Hash] Telemetry insights
    def calculate_telemetry_insights
      trace_backend = Tasker::Telemetry::TraceBackend.instance
      log_backend = Tasker::Telemetry::LogBackend.instance

      {
        trace_stats: trace_backend.stats,
        log_stats: log_backend.stats,
        event_router_stats: Tasker::Telemetry::EventRouter.instance.routing_stats
      }
    end

    # Calculate bottleneck analytics for specified scope and period
    #
    # @param scope_params [Hash] Scope parameters
    # @param period_hours [Integer] Analysis period in hours
    # @return [Hash] Bottleneck analysis data
    def calculate_bottleneck_analytics(scope_params, period_hours)
      since_time = period_hours.hours.ago

      # Build base query with scope filtering
      base_query = apply_scope_filters(Task.includes(:named_task, workflow_steps: :workflow_step_transitions), scope_params)
                   .where('tasker_tasks.created_at > ?', since_time)

      {
        scope_summary: calculate_scope_summary(base_query),
        bottleneck_analysis: {
          slowest_tasks: find_slowest_tasks(base_query),
          slowest_steps: find_slowest_steps(base_query, since_time),
          error_patterns: analyze_error_patterns(base_query),
          dependency_bottlenecks: analyze_dependency_bottlenecks(base_query)
        },
        performance_distribution: calculate_performance_distribution(base_query),
        recommendations: generate_bottleneck_recommendations(base_query)
      }
    end

    # Apply scope filters using the new ActiveRecord scopes
    #
    # @param query [ActiveRecord::Relation] Base query
    # @param scope_params [Hash] Scope parameters
    # @return [ActiveRecord::Relation] Filtered query
    def apply_scope_filters(query, scope_params)
      # Use the new scopes for cleaner and more efficient filtering
      query = query.in_namespace(scope_params[:namespace]) if scope_params[:namespace]
      query = query.with_task_name(scope_params[:name]) if scope_params[:name]
      query = query.with_version(scope_params[:version]) if scope_params[:version]

      query
    end

    # Calculate health score based on recent system performance using ActiveRecord
    #
    # @return [Float] Health score between 0.0 and 1.0
    def calculate_health_score_from_metrics
      # Simple health score calculation based on recent performance
      recent_tasks = Task.created_since(1.hour.ago).count
      return 1.0 if recent_tasks.zero?

      recent_failures = Task.failed_since(1.hour.ago).count
      failure_rate = recent_failures.to_f / recent_tasks

      # Health score inversely related to failure rate
      (1.0 - failure_rate).clamp(0.0, 1.0).round(3)
    end

    # Additional helper methods for bottleneck analysis...
    def calculate_scope_summary(query)
      # Use the filtered query to calculate real scope summary
      total_tasks = query.count
      unique_task_types = query.joins(:named_task).distinct.count('tasker_named_tasks.name')
      
      {
        total_tasks: total_tasks,
        unique_task_types: unique_task_types,
        time_span_hours: 24.0  # This is based on the analysis_period parameter
      }
    rescue StandardError => e
      Rails.logger.error "Error in calculate_scope_summary: #{e.message}"
      {
        total_tasks: 0,
        unique_task_types: 0,
        time_span_hours: 24.0
      }
    end

    def find_slowest_tasks(query)
      # Get tasks with duration calculation, limited to top 10 slowest
      tasks_with_duration = query.joins(named_task: :task_namespace)
                                 .joins('LEFT JOIN tasker_task_transitions tt ON tt.task_id = tasker_tasks.task_id AND tt.most_recent = true')
                                 .select([
                                   'tasker_tasks.task_id',
                                   'tasker_named_tasks.name as task_name',
                                   'tasker_task_namespaces.name as namespace_name',
                                   'CASE 
                                     WHEN tt.to_state = \'complete\' THEN EXTRACT(EPOCH FROM (tt.created_at - tasker_tasks.created_at))
                                     ELSE EXTRACT(EPOCH FROM (NOW() - tasker_tasks.created_at))
                                   END as duration_seconds'
                                 ])
                                 .order('duration_seconds DESC')
                                 .limit(10)

      # Convert to hash format and add step counts
      tasks_with_duration.map do |task|
        step_counts = calculate_step_counts_for_task(task.task_id)
        
        {
          task_id: task.task_id,
          duration_seconds: task.duration_seconds.to_f.round(1),
          task_name: task.task_name,
          namespace_name: task.namespace_name,
          step_count: step_counts[:total],
          completed_steps: step_counts[:completed],
          error_steps: step_counts[:error]
        }
      end
    rescue StandardError => e
      Rails.logger.error "Error in find_slowest_tasks: #{e.message}"
      []
    end

    def find_slowest_steps(query, since_time)
      # Get workflow steps for tasks in the query with duration calculations
      task_ids = query.pluck(:task_id)
      return [] if task_ids.empty?

      slowest_steps = WorkflowStep.joins(:named_step, task: { named_task: :task_namespace })
                                  .joins('LEFT JOIN tasker_workflow_step_transitions wst_start ON wst_start.workflow_step_id = tasker_workflow_steps.workflow_step_id AND wst_start.to_state = \'in_progress\'')
                                  .joins('LEFT JOIN tasker_workflow_step_transitions wst_complete ON wst_complete.workflow_step_id = tasker_workflow_steps.workflow_step_id AND wst_complete.to_state IN (\'complete\', \'resolved_manually\') AND wst_complete.most_recent = true')
                                  .where(task_id: task_ids)
                                  .where('tasker_workflow_steps.created_at >= ?', since_time)
                                  .where.not(wst_complete: { id: nil }) # Only completed steps
                                  .select([
                                    'tasker_workflow_steps.workflow_step_id',
                                    'tasker_named_steps.name as step_name',
                                    'tasker_named_tasks.name as task_name',
                                    'tasker_workflow_steps.attempts',
                                    'tasker_workflow_steps.retryable',
                                    'CASE 
                                       WHEN wst_complete.created_at IS NOT NULL AND wst_start.created_at IS NOT NULL 
                                       THEN EXTRACT(EPOCH FROM (wst_complete.created_at - wst_start.created_at))
                                       ELSE EXTRACT(EPOCH FROM (wst_complete.created_at - tasker_workflow_steps.created_at))
                                     END as duration_seconds'
                                  ])
                                  .order('duration_seconds DESC')
                                  .limit(10)

      slowest_steps.map do |step|
        {
          workflow_step_id: step.workflow_step_id,
          duration_seconds: step.duration_seconds.to_f.round(1),
          step_name: step.step_name,
          task_name: step.task_name,
          attempts: step.attempts || 0,
          retryable: step.retryable.nil? ? true : step.retryable
        }
      end
    rescue StandardError => e
      Rails.logger.error "Error in find_slowest_steps: #{e.message}"
      []
    end

    def analyze_error_patterns(query)
      # Analyze error patterns from tasks in the query
      task_ids = query.pluck(:task_id)
      return default_error_pattern if task_ids.empty?

      # Get failed steps and analyze patterns
      failed_steps = WorkflowStep.joins('LEFT JOIN tasker_workflow_step_transitions wst ON wst.workflow_step_id = tasker_workflow_steps.workflow_step_id AND wst.most_recent = true')
                                 .where(task_id: task_ids)
                                 .where('wst.to_state = ?', 'error')

      total_errors = failed_steps.count
      retry_successful = failed_steps.where('tasker_workflow_steps.attempts > 1').count
      
      {
        total_errors: total_errors,
        recent_error_rate: calculate_error_rate_for_tasks(task_ids),
        common_error_types: extract_common_error_types(failed_steps),
        retry_success_rate: total_errors > 0 ? (retry_successful.to_f / total_errors * 100).round(1) : 0.0
      }
    rescue StandardError => e
      Rails.logger.error "Error in analyze_error_patterns: #{e.message}"
      default_error_pattern
    end

    def analyze_dependency_bottlenecks(query)
      # Analyze dependency-related bottlenecks
      task_ids = query.pluck(:task_id)
      return default_dependency_bottlenecks if task_ids.empty?

      # Find steps that are waiting for dependencies
      pending_steps = WorkflowStep.joins('LEFT JOIN tasker_workflow_step_transitions wst ON wst.workflow_step_id = tasker_workflow_steps.workflow_step_id AND wst.most_recent = true')
                                  .joins(:named_step)
                                  .where(task_id: task_ids)
                                  .where('wst.to_state = ? OR wst.to_state IS NULL', 'pending')

      blocking_count = pending_steps.joins('JOIN tasker_workflow_step_edges wse ON wse.to_step_id = tasker_workflow_steps.workflow_step_id').count
      
      # Calculate average wait time for pending steps
      avg_wait = pending_steps.where('tasker_workflow_steps.created_at < ?', 5.minutes.ago)
                              .average('EXTRACT(EPOCH FROM (NOW() - tasker_workflow_steps.created_at))')

      {
        blocking_dependencies: blocking_count,
        avg_wait_time: avg_wait&.to_f&.round(1) || 0.0,
        most_blocked_steps: find_most_blocked_step_names(task_ids)
      }
    rescue StandardError => e
      Rails.logger.error "Error in analyze_dependency_bottlenecks: #{e.message}"
      default_dependency_bottlenecks
    end

    def calculate_performance_distribution(query)
      # Calculate actual performance distribution from task durations
      task_ids = query.pluck(:task_id)
      return default_performance_distribution if task_ids.empty?

      completed_tasks = fetch_completed_task_durations(task_ids)
      return default_performance_distribution if completed_tasks.empty?

      build_performance_distribution(completed_tasks)
    rescue StandardError => e
      Rails.logger.error "Error in calculate_performance_distribution: #{e.message}"
      default_performance_distribution
    end

    def fetch_completed_task_durations(task_ids)
      Task.joins(
        'LEFT JOIN tasker_task_transitions tt ON tt.task_id = tasker_tasks.task_id AND tt.most_recent = true'
      ).where(task_id: task_ids)
       .where(tt: { to_state: 'complete' })
       .select('EXTRACT(EPOCH FROM (tt.created_at - tasker_tasks.created_at)) as duration_seconds')
       .filter_map { |task| task.duration_seconds&.to_f }
    end

    def build_performance_distribution(completed_tasks)
      sorted_durations = completed_tasks.sort

      percentiles = {
        p50: calculate_percentile(sorted_durations, 50),
        p95: calculate_percentile(sorted_durations, 95),
        p99: calculate_percentile(sorted_durations, 99)
      }

      distribution_buckets = [
        { range: '0-10s', count: completed_tasks.count { |d| d <= 10 } },
        { range: '10-30s', count: completed_tasks.count { |d| d > 10 && d <= 30 } },
        { range: '30s+', count: completed_tasks.count { |d| d > 30 } }
      ]

      { percentiles: percentiles, distribution_buckets: distribution_buckets }
    end

    def generate_bottleneck_recommendations(query)
      # Generate recommendations based on actual bottleneck analysis
      recommendations = []
      
      # Analyze slow tasks for recommendations
      slow_tasks = find_slowest_tasks(query)
      if slow_tasks.any? { |task| task[:duration_seconds] > 60 }
        recommendations << "Consider optimizing long-running tasks (#{slow_tasks.first[:duration_seconds]}s average)"
      end
      
      # Analyze error patterns
      error_analysis = analyze_error_patterns(query)
      if error_analysis[:total_errors] > 5
        recommendations << "High error rate detected (#{error_analysis[:total_errors]} errors). Review error handling."
      end
      
      # Default recommendations if none generated
      if recommendations.empty?
        recommendations = [
          'Monitor task performance trends regularly',
          'Review timeout configurations for network operations',
          'Consider implementing caching for repeated operations'
        ]
      end
      
      recommendations.take(5) # Limit to 5 recommendations
    rescue StandardError => e
      Rails.logger.error "Error generating recommendations: #{e.message}"
      ['Monitor system performance regularly']
    end

    # Helper method to extract scope parameters from controller params
    # This replaces the complex query parsing approach
    def extract_scope_from_query(_query)
      # Extract scope from the controller params instead of parsing the query
      extract_scope_parameters
    end

    # Helper methods for performance calculations using ActiveRecord
    def calculate_completion_rate(since_time)
      total_tasks = Task.created_since(since_time).count
      return 0.0 if total_tasks.zero?

      completed_tasks = Task.completed_since(since_time).count
      (completed_tasks.to_f / total_tasks * 100).round(2)
    end

    def calculate_error_rate(since_time)
      total_tasks = Task.created_since(since_time).count
      return 0.0 if total_tasks.zero?

      failed_tasks = Task.failed_since(since_time).count
      (failed_tasks.to_f / total_tasks * 100).round(2)
    end

    def calculate_avg_task_duration(since_time)
      # Calculate real average task duration
      completed_tasks = Task.joins('LEFT JOIN tasker_task_transitions tt ON tt.task_id = tasker_tasks.task_id AND tt.most_recent = true')
                           .where('tasker_tasks.created_at >= ?', since_time)
                           .where('tt.to_state = ?', 'complete')
                           .average('EXTRACT(EPOCH FROM (tt.created_at - tasker_tasks.created_at))')
      
      completed_tasks&.to_f&.round(1) || 0.0
    rescue StandardError => e
      Rails.logger.error "Error calculating avg task duration: #{e.message}"
      0.0
    end

    def calculate_avg_step_duration(since_time)
      # Calculate real average step duration
      completed_steps = WorkflowStep.joins('LEFT JOIN tasker_workflow_step_transitions wst ON wst.workflow_step_id = tasker_workflow_steps.workflow_step_id AND wst.most_recent = true')
                                   .where('tasker_workflow_steps.created_at >= ?', since_time)
                                   .where('wst.to_state IN (?)', ['complete', 'resolved_manually'])
                                   .average('EXTRACT(EPOCH FROM (wst.created_at - tasker_workflow_steps.created_at))')
      
      completed_steps&.to_f&.round(1) || 0.0
    rescue StandardError => e
      Rails.logger.error "Error calculating avg step duration: #{e.message}"
      0.0
    end

    # Helper methods for complex analytics calculations
    def calculate_step_counts_for_task(task_id)
      step_counts = WorkflowStep.joins('LEFT JOIN tasker_workflow_step_transitions wst ON wst.workflow_step_id = tasker_workflow_steps.workflow_step_id AND wst.most_recent = true')
                               .where(task_id: task_id)
                               .group('wst.to_state')
                               .count

      {
        total: step_counts.values.sum,
        completed: step_counts['complete'].to_i + step_counts['resolved_manually'].to_i,
        error: step_counts['error'].to_i
      }
    rescue StandardError => e
      Rails.logger.error "Error calculating step counts for task #{task_id}: #{e.message}"
      { total: 0, completed: 0, error: 0 }
    end

    def calculate_error_rate_for_tasks(task_ids)
      return 0.0 if task_ids.empty?
      
      total_tasks = task_ids.size
      failed_tasks = Task.joins('LEFT JOIN tasker_task_transitions tt ON tt.task_id = tasker_tasks.task_id AND tt.most_recent = true')
                        .where(task_id: task_ids)
                        .where('tt.to_state = ?', 'error')
                        .count
      
      (failed_tasks.to_f / total_tasks * 100).round(1)
    rescue StandardError => e
      Rails.logger.error "Error calculating error rate: #{e.message}"
      0.0
    end

    def extract_common_error_types(failed_steps)
      # For now, return common error categories
      # In the future, this could analyze actual error messages
      %w[timeout validation network]
    end

    def find_most_blocked_step_names(task_ids)
      # Find step names that are frequently blocked by dependencies
      blocked_steps = WorkflowStep.joins(:named_step)
                                 .joins('LEFT JOIN tasker_workflow_step_transitions wst ON wst.workflow_step_id = tasker_workflow_steps.workflow_step_id AND wst.most_recent = true')
                                 .joins('JOIN tasker_workflow_step_edges wse ON wse.to_step_id = tasker_workflow_steps.workflow_step_id')
                                 .where(task_id: task_ids)
                                 .where('wst.to_state = ? OR wst.to_state IS NULL', 'pending')
                                 .group('tasker_named_steps.name')
                                 .order(Arel.sql('COUNT(*) DESC'))
                                 .limit(3)
                                 .pluck('tasker_named_steps.name')
      
      blocked_steps.presence || ['data_validation', 'external_api_calls']
    rescue StandardError => e
      Rails.logger.error "Error finding blocked step names: #{e.message}"
      ['data_validation', 'external_api_calls']
    end

    def calculate_percentile(sorted_array, percentile)
      return 0.0 if sorted_array.empty?
      
      index = (percentile / 100.0 * (sorted_array.length - 1)).round
      sorted_array[index].to_f.round(1)
    end

    # Default fallback methods for error conditions
    def default_error_pattern
      {
        total_errors: 0,
        recent_error_rate: 0.0,
        common_error_types: [],
        retry_success_rate: 0.0
      }
    end

    def default_dependency_bottlenecks
      {
        blocking_dependencies: 0,
        avg_wait_time: 0.0,
        most_blocked_steps: []
      }
    end

    def default_performance_distribution
      {
        percentiles: { p50: 0.0, p95: 0.0, p99: 0.0 },
        distribution_buckets: [
          { range: '0-10s', count: 0 },
          { range: '10-30s', count: 0 },
          { range: '30s+', count: 0 }
        ]
      }
    end

    # Override the resource name for authorization
    # Maps analytics actions to analytics resource
    #
    # @return [String] The resource name for authorization
    def tasker_resource_name
      Tasker::Authorization::ResourceConstants::RESOURCES::ANALYTICS
    end

    # Override the action name for authorization
    # Maps all actions to index permission for analytics
    #
    # @return [Symbol] The action name for authorization
    def tasker_action_name
      Tasker::Authorization::ResourceConstants::ACTIONS::INDEX
    end

    # Override authentication check for analytics endpoint
    # Uses telemetry configuration for consistency with metrics
    #
    # @return [Boolean] True if authentication should be skipped
    def skip_authentication?
      !Tasker.configuration.telemetry.metrics_auth_required
    end

    # Override authorization check for analytics endpoint
    # Uses telemetry configuration for consistency with metrics
    #
    # @return [Boolean] True if authorization should be skipped
    def skip_authorization?
      !Tasker.configuration.telemetry.metrics_auth_required
    end

    # Set appropriate cache control headers for analytics endpoints
    def set_cache_headers
      response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
      response.headers['Pragma'] = 'no-cache'
      response.headers['Expires'] = '0'
    end
  end
end
