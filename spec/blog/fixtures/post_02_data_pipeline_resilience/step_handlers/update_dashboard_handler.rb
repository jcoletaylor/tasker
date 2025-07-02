module DataPipeline
  module StepHandlers
    class UpdateDashboardHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        insights_data = step_results(sequence, 'generate_insights')

        log_structured_info("Starting dashboard update", {
          insights_available: insights_data.present?,
          insights_keys: insights_data.keys
        })

        # Validate we have insights data
        if insights_data.empty?
          log_structured_error("No insights data available for dashboard update", {
            sequence_steps: sequence.workflow_step_sequences.last.workflow_steps.map(&:name)
          })
          raise StandardError, "Cannot update dashboard without insights data"
        end

        dashboards_updated = []
        update_errors = []

        begin
          # Update executive dashboard
          executive_result = update_executive_dashboard(insights_data)
          dashboards_updated << executive_result

          # Update customer analytics dashboard
          customer_result = update_customer_dashboard(insights_data)
          dashboards_updated << customer_result

          # Update product analytics dashboard
          product_result = update_product_dashboard(insights_data)
          dashboards_updated << product_result

          # Update operational dashboard if we have alerts
          if insights_data['performance_alerts']&.any?
            operational_result = update_operational_dashboard(insights_data)
            dashboards_updated << operational_result
          end

        rescue StandardError => e
          log_structured_error("Dashboard update failed", {
            error: e.message,
            error_class: e.class.name,
            dashboards_attempted: dashboards_updated.length
          })
          raise e  # Let Tasker handle retries
        end

        # Calculate update statistics
        successful_updates = dashboards_updated.count { |d| d[:status] == 'success' }
        total_updates = dashboards_updated.length

        result = {
          status: successful_updates == total_updates ? 'success' : 'partial_success',
          dashboards_updated: dashboards_updated.map { |d| d[:dashboard_name] },
          update_details: dashboards_updated,
          total_dashboards: total_updates,
          successful_updates: successful_updates,
          failed_updates: total_updates - successful_updates,
          updated_at: Time.current.iso8601,
          processing_stats: {
            processing_time_seconds: step.duration_seconds,
            data_points_updated: dashboards_updated.sum { |d| d[:data_points_updated] || 0 }
          }
        }

        log_structured_info("Dashboard update completed", {
          successful_updates: successful_updates,
          total_updates: total_updates,
          processing_time_seconds: step.duration_seconds
        })

        # Fire event for dashboard refresh notifications (handled by event subscribers)
        publish_event('dashboards_updated', {
          dashboards_updated: dashboards_updated,
          update_summary: {
            successful: successful_updates,
            total: total_updates,
            status: result[:status]
          },
          task_id: task.id
        })

        result
      end

      private

      def step_results(sequence, step_name)
        step = sequence.steps.find { |s| s.name == step_name }
        step&.results || {}
      end

      def update_executive_dashboard(insights_data)
        executive_summary = insights_data['executive_summary'] || {}

        log_structured_info("Updating executive dashboard", {
          summary_keys: executive_summary.keys
        })

        # Business logic: Update executive dashboard data
        dashboard_data = {
          period_overview: executive_summary['period_overview'] || {},
          customer_highlights: executive_summary['customer_highlights'] || {},
          product_highlights: executive_summary['product_highlights'] || {},
          key_metrics: {
            revenue: executive_summary.dig('period_overview', 'total_revenue') || 0,
            customers: executive_summary.dig('period_overview', 'total_customers_analyzed') || 0,
            orders: executive_summary.dig('period_overview', 'total_orders_processed') || 0,
            avg_order_value: executive_summary.dig('customer_highlights', 'average_order_value') || 0
          },
          alerts_summary: {
            critical_count: insights_data['performance_alerts']&.count { |a| a['severity'] == 'critical' } || 0,
            warning_count: insights_data['performance_alerts']&.count { |a| a['severity'] == 'warning' } || 0
          },
          last_updated: Time.current.iso8601
        }

        # Store in dashboard data store (business logic)
        DashboardDataStore.update('executive_dashboard', dashboard_data)

        {
          dashboard_name: 'executive_dashboard',
          status: 'success',
          data_points_updated: dashboard_data.keys.length,
          last_updated: Time.current.iso8601
        }
      end

      def update_customer_dashboard(insights_data)
        customer_metrics = insights_data['customer_analysis'] || {}

        log_structured_info("Updating customer dashboard", {
          metrics_available: customer_metrics.present?
        })

        dashboard_data = {
          customer_segments: customer_metrics['segment_breakdown'] || {},
          lifetime_value_analysis: customer_metrics['ltv_analysis'] || {},
          retention_metrics: customer_metrics['retention_metrics'] || {},
          acquisition_trends: customer_metrics['acquisition_trends'] || {},
          churn_analysis: customer_metrics['churn_analysis'] || {},
          top_customers: customer_metrics['top_customers'] || [],
          last_updated: Time.current.iso8601
        }

        DashboardDataStore.update('customer_dashboard', dashboard_data)

        {
          dashboard_name: 'customer_dashboard',
          status: 'success',
          data_points_updated: dashboard_data.keys.length,
          last_updated: Time.current.iso8601
        }
      end

      def update_product_dashboard(insights_data)
        product_analysis = insights_data['product_analysis'] || {}

        log_structured_info("Updating product dashboard", {
          analysis_available: product_analysis.present?
        })

        dashboard_data = {
          top_products: product_analysis['top_performing_products'] || [],
          category_performance: product_analysis['category_breakdown'] || {},
          inventory_alerts: product_analysis['inventory_recommendations'] || [],
          pricing_insights: product_analysis['pricing_analysis'] || {},
          seasonal_trends: product_analysis['seasonal_patterns'] || {},
          last_updated: Time.current.iso8601
        }

        DashboardDataStore.update('product_dashboard', dashboard_data)

        {
          dashboard_name: 'product_dashboard',
          status: 'success',
          data_points_updated: dashboard_data.keys.length,
          last_updated: Time.current.iso8601
        }
      end

      def update_operational_dashboard(insights_data)
        alerts = insights_data['performance_alerts'] || []

        log_structured_info("Updating operational dashboard", {
          alerts_count: alerts.length
        })

        dashboard_data = {
          active_alerts: alerts,
          alert_summary: {
            critical: alerts.count { |a| a['severity'] == 'critical' },
            warning: alerts.count { |a| a['severity'] == 'warning' },
            info: alerts.count { |a| a['severity'] == 'info' }
          },
          system_health: {
            pipeline_status: 'healthy',
            last_successful_run: Time.current.iso8601,
            data_freshness: 'current'
          },
          recommendations: insights_data['business_recommendations'] || [],
          last_updated: Time.current.iso8601
        }

        DashboardDataStore.update('operational_dashboard', dashboard_data)

        {
          dashboard_name: 'operational_dashboard',
          status: 'success',
          data_points_updated: dashboard_data.keys.length,
          last_updated: Time.current.iso8601
        }
      end

      def log_structured_info(message, **context)
        log_structured(:info, message, step_name: 'update_dashboard', **context)
      end

      def log_structured_error(message, **context)
        log_structured(:error, message, step_name: 'update_dashboard', **context)
      end
    end
  end
end

# Mock dashboard data store for demo purposes
class DashboardDataStore
  def self.update(dashboard_name, data)
    Rails.logger.info("Dashboard Updated: #{dashboard_name}")
    Rails.logger.info("Data: #{data.to_json}")

    # In a real implementation, this would update the actual dashboard data store
    # Could be Redis, database, or dashboard service API
    true
  end
end
