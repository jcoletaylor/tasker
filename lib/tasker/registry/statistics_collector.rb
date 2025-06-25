# typed: false
# frozen_string_literal: true

require_relative '../concerns/structured_logging'

module Tasker
  module Registry
    # Comprehensive statistics collection for all registry systems
    #
    # Provides unified observability, performance monitoring, and
    # health checking across all registry components.
    class StatisticsCollector
      include Tasker::Concerns::StructuredLogging

      class << self
        # Collect comprehensive statistics from all registries
        #
        # @return [Hash] Complete statistics for all registries
        def collect_all_registry_stats
          registries = discover_all_registries

          stats = {
            collection_timestamp: Time.current,
            total_registries: registries.size,
            registries: {}
          }

          registries.each do |registry|
            registry_stats = collect_registry_stats(registry)
            stats[:registries][registry_stats[:registry_name]] = registry_stats
          end

          # Calculate aggregated metrics
          stats[:aggregated] = calculate_aggregated_metrics(stats[:registries])

          stats
        end

        # Collect statistics from a specific registry
        #
        # @param registry [BaseRegistry] Registry to collect stats from
        # @return [Hash] Registry statistics with performance metrics
        def collect_registry_stats(registry)
          base_stats = registry.stats
          health_check = registry.health_check

          {
            **base_stats,
            health: health_check,
            performance: measure_registry_performance(registry),
            usage_patterns: analyze_usage_patterns(registry),
            recommendations: generate_recommendations(registry)
          }
        end

        # Get health status for all registries
        #
        # @return [Hash] Health status summary
        def health_summary
          registries = discover_all_registries

          health_results = registries.map do |registry|
            {
              registry_name: registry.class.name.demodulize.underscore,
              healthy: registry.healthy?,
              health_details: registry.health_check
            }
          end

          {
            overall_healthy: health_results.all? { |result| result[:healthy] },
            registry_count: registries.size,
            healthy_registries: health_results.count { |result| result[:healthy] },
            unhealthy_registries: health_results.reject { |result| result[:healthy] },
            registries: health_results,
            checked_at: Time.current
          }
        end

        # Find registries matching criteria
        #
        # @param criteria [Hash] Search criteria
        # @option criteria [String] :name_pattern Registry name pattern
        # @option criteria [Symbol] :health_status Health status filter (:healthy, :unhealthy)
        # @option criteria [Integer] :min_items Minimum item count
        # @return [Array<BaseRegistry>] Matching registries
        def find_registries(criteria = {})
          registries = discover_all_registries

          if criteria[:name_pattern]
            pattern = Regexp.new(criteria[:name_pattern], Regexp::IGNORECASE)
            registries = registries.select { |registry| registry.class.name.match?(pattern) }
          end

          if criteria[:health_status]
            case criteria[:health_status]
            when :healthy
              registries = registries.select(&:healthy?)
            when :unhealthy
              registries = registries.reject(&:healthy?)
            end
          end

          if criteria[:min_items]
            registries = registries.select do |registry|
              registry.stats[:total_handlers] ||
                registry.stats[:total_plugins] ||
                registry.stats[:total_subscribers] || criteria[:min_items] <= 0
            end
          end

          registries
        end

        # Generate performance report
        #
        # @return [Hash] Performance analysis across all registries
        def performance_report
          registries = discover_all_registries

          performance_data = registries.map do |registry|
            {
              registry_name: registry.class.name.demodulize.underscore,
              performance: measure_registry_performance(registry),
              item_count: calculate_registry_item_count(registry)
            }
          end

          {
            report_timestamp: Time.current,
            total_registries: registries.size,
            performance_data: performance_data,
            performance_summary: calculate_performance_summary(performance_data)
          }
        end

        private

        # Discover all available registries
        #
        # @return [Array<BaseRegistry>] All registry instances
        def discover_all_registries
          registries = []

          # Core registries
          registries << Tasker::HandlerFactory.instance if defined?(Tasker::HandlerFactory)
          registries << Tasker::Registry::SubscriberRegistry.instance if defined?(Tasker::Registry::SubscriberRegistry)

          # Telemetry registries
          if defined?(Tasker::Telemetry)
            registries << Tasker::Telemetry::PluginRegistry.instance if defined?(Tasker::Telemetry::PluginRegistry)
            if defined?(Tasker::Telemetry::ExportCoordinator)
              registries << Tasker::Telemetry::ExportCoordinator.instance
            end
          end

          registries.compact
        end

        # Measure performance metrics for a registry
        #
        # @param registry [BaseRegistry] Registry to measure
        # @return [Hash] Performance metrics
        def measure_registry_performance(registry)
          # Measure stats collection time
          stats_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          registry.stats
          stats_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - stats_start

          # Measure health check time
          health_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          registry.health_check
          health_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - health_start

          {
            stats_response_time_ms: (stats_duration * 1000).round(2),
            health_check_time_ms: (health_duration * 1000).round(2),
            thread_safe: true,
            last_measured: Time.current
          }
        end

        # Analyze usage patterns for a registry
        #
        # @param registry [BaseRegistry] Registry to analyze
        # @return [Hash] Usage pattern analysis
        def analyze_usage_patterns(registry)
          stats = registry.stats

          {
            utilization: calculate_utilization(stats),
            distribution: calculate_distribution(stats),
            growth_trend: 'stable', # Would track over time in production
            efficiency_score: calculate_efficiency_score(stats)
          }
        end

        # Calculate utilization level
        #
        # @param stats [Hash] Registry statistics
        # @return [String] Utilization level
        def calculate_utilization(stats)
          total_items = stats[:total_handlers] || stats[:total_plugins] || stats[:total_subscribers] || 0

          case total_items
          when 0 then 'empty'
          when 1..5 then 'low'
          when 6..20 then 'medium'
          when 21..50 then 'high'
          else 'very_high'
          end
        end

        # Calculate distribution pattern
        #
        # @param stats [Hash] Registry statistics
        # @return [String] Distribution pattern
        def calculate_distribution(stats)
          if stats[:handlers_by_namespace]
            analyze_namespace_distribution(stats[:handlers_by_namespace])
          elsif stats[:plugins_by_format]
            analyze_format_distribution(stats[:plugins_by_format])
          elsif stats[:subscribers_by_event]
            analyze_event_distribution(stats[:subscribers_by_event])
          else
            'unknown'
          end
        end

        # Analyze namespace distribution for handlers
        #
        # @param handlers_by_namespace [Hash] Handler distribution data
        # @return [String] Distribution pattern
        def analyze_namespace_distribution(handlers_by_namespace)
          return 'empty' if handlers_by_namespace.empty?

          values = handlers_by_namespace.values
          return 'single' if values.size == 1

          avg = values.sum.to_f / values.size
          variance = values.sum { |v| (v - avg)**2 } / values.size

          variance < 2 ? 'even' : 'skewed'
        end

        # Analyze format distribution for plugins
        #
        # @param plugins_by_format [Hash] Plugin distribution data
        # @return [String] Distribution pattern
        def analyze_format_distribution(plugins_by_format)
          return 'empty' if plugins_by_format.empty?

          values = plugins_by_format.values
          values.uniq.size == 1 ? 'uniform' : 'varied'
        end

        # Analyze event distribution for subscribers
        #
        # @param subscribers_by_event [Hash] Subscriber distribution data
        # @return [String] Distribution pattern
        def analyze_event_distribution(subscribers_by_event)
          return 'empty' if subscribers_by_event.empty?

          values = subscribers_by_event.values
          avg = values.sum.to_f / values.size
          variance = values.sum { |v| (v - avg)**2 } / values.size

          variance < 1 ? 'balanced' : 'unbalanced'
        end

        # Calculate efficiency score
        #
        # @param stats [Hash] Registry statistics
        # @return [Float] Efficiency score (0.0 - 1.0)
        def calculate_efficiency_score(stats)
          # Simple efficiency calculation based on utilization and distribution
          base_score = 0.5

          # Adjust for utilization
          utilization = calculate_utilization(stats)
          utilization_bonus = case utilization
                              when 'empty' then -0.3
                              when 'low' then 0.0
                              when 'medium' then 0.2
                              when 'high' then 0.3
                              when 'very_high' then 0.1
                              end

          # Adjust for distribution
          distribution = calculate_distribution(stats)
          distribution_bonus = case distribution
                               when 'even', 'balanced', 'uniform' then 0.2
                               when 'skewed', 'unbalanced', 'varied' then -0.1
                               else 0.0
                               end

          [0.0, [1.0, base_score + utilization_bonus + distribution_bonus].min].max
        end

        # Generate recommendations for a registry
        #
        # @param registry [BaseRegistry] Registry to analyze
        # @return [Array<String>] Recommendations
        def generate_recommendations(registry)
          recommendations = []
          stats = registry.stats

          # Health recommendations
          recommendations << 'Registry health check failed - investigate immediately' unless registry.healthy?

          # Utilization recommendations
          utilization = calculate_utilization(stats)
          case utilization
          when 'empty'
            recommendations << "Registry is empty - consider if it's needed"
          when 'very_high'
            recommendations << 'High utilization - monitor performance and consider optimization'
          end

          # Distribution recommendations
          distribution = calculate_distribution(stats)
          case distribution
          when 'skewed', 'unbalanced'
            recommendations << 'Uneven distribution detected - consider rebalancing'
          end

          recommendations.empty? ? ['Registry is operating optimally'] : recommendations
        end

        # Calculate aggregated metrics across all registries
        #
        # @param registries_stats [Hash] Statistics for all registries
        # @return [Hash] Aggregated metrics
        def calculate_aggregated_metrics(registries_stats)
          total_items = 0
          healthy_count = 0
          efficiency_scores = []

          registries_stats.each_value do |stats|
            total_items += stats[:total_handlers] || stats[:total_plugins] || stats[:total_subscribers] || 0
            healthy_count += 1 if stats[:health][:healthy]
            efficiency_scores << stats[:usage_patterns][:efficiency_score]
          end

          {
            total_registered_items: total_items,
            overall_health_percentage: registries_stats.empty? ? 0 : (healthy_count.to_f / registries_stats.size * 100).round(1),
            average_efficiency_score: efficiency_scores.empty? ? 0 : (efficiency_scores.sum / efficiency_scores.size).round(3),
            registry_count: registries_stats.size
          }
        end

        # Calculate item count for a registry
        #
        # @param registry [BaseRegistry] Registry to count items for
        # @return [Integer] Total item count
        def calculate_registry_item_count(registry)
          stats = registry.stats
          stats[:total_handlers] || stats[:total_plugins] || stats[:total_subscribers] || 0
        end

        # Calculate performance summary
        #
        # @param performance_data [Array<Hash>] Performance data for all registries
        # @return [Hash] Performance summary
        def calculate_performance_summary(performance_data)
          response_times = performance_data.map { |data| data[:performance][:stats_response_time_ms] }

          return { summary: 'no_data' } if response_times.empty?

          {
            average_response_time_ms: (response_times.sum / response_times.size).round(2),
            max_response_time_ms: response_times.max,
            min_response_time_ms: response_times.min,
            total_items_managed: performance_data.sum { |data| data[:item_count] }
          }
        end
      end
    end
  end
end
