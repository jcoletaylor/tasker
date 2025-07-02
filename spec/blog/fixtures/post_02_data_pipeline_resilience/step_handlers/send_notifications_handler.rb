module DataPipeline
  module StepHandlers
    class SendNotificationsHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        insights_data = step_results(sequence, 'generate_insights')
        dashboard_data = step_results(sequence, 'update_dashboard')

        notification_channels = task.context['notification_channels'] || ['#data-team']

        log_structured_info("Processing notification requirements", {
          channels: notification_channels,
          insights_available: insights_data.present?,
          dashboard_updated: dashboard_data.present?
        })

        # Business logic: Determine what notifications need to be sent
        # The actual sending is handled by event subscribers
        notification_requirements = build_notification_requirements(
          insights_data,
          dashboard_data,
          notification_channels
        )

        # Record the notification requirements (this is the business logic)
        notification_record = {
          status: 'scheduled',
          requirements: notification_requirements,
          channels_configured: notification_channels,
          total_notifications: notification_requirements.length,
          scheduled_at: Time.current.iso8601,
          pipeline_task_id: task.id
        }

        log_structured_info("Notification requirements processed", {
          total_notifications: notification_requirements.length,
          types: notification_requirements.map { |n| n[:type] }.uniq
        })

        # Fire event for actual notification sending (handled by event subscribers)
        # This ensures notifications don't block the pipeline if they fail
        publish_event('pipeline_notifications_ready', {
          notification_requirements: notification_requirements,
          channels: notification_channels,
          insights_data: insights_data,
          dashboard_data: dashboard_data,
          task_id: task.id
        })

        notification_record
      end

      private

      def step_results(sequence, step_name)
        step = sequence.steps.find { |s| s.name == step_name }
        step&.results || {}
      end

      def build_notification_requirements(insights_data, dashboard_data, channels)
        requirements = []

        # Always send completion notification
        requirements << {
          type: 'completion',
          priority: 'standard',
          channels: channels,
          data: {
            insights_summary: extract_insights_summary(insights_data),
            dashboard_summary: extract_dashboard_summary(dashboard_data)
          }
        }

        # Add alert notifications for critical issues
        if insights_data['performance_alerts']&.any?
          critical_alerts = insights_data['performance_alerts'].select { |a| a['severity'] == 'critical' }
          warning_alerts = insights_data['performance_alerts'].select { |a| a['severity'] == 'warning' }

          critical_alerts.each do |alert|
            requirements << {
              type: 'critical_alert',
              priority: 'urgent',
              alert_data: alert,
              escalation_required: true
            }
          end

          warning_alerts.each do |alert|
            requirements << {
              type: 'warning_alert',
              priority: 'high',
              alert_data: alert,
              escalation_required: false
            }
          end
        end

        # Add recommendation notifications
        if insights_data['business_recommendations']&.any?
          insights_data['business_recommendations'].each do |recommendation|
            requirements << {
              type: 'recommendation',
              priority: recommendation['priority'] || 'medium',
              recommendation_data: recommendation,
              target_team: determine_target_team(recommendation['type'])
            }
          end
        end

        # Add summary email requirement
        if should_send_summary_email?(insights_data)
          requirements << {
            type: 'summary_email',
            priority: 'standard',
            recipients: determine_email_recipients(insights_data),
            data: {
              executive_summary: insights_data['executive_summary'],
              period_covered: extract_period_info(insights_data)
            }
          }
        end

        requirements
      end

      def extract_insights_summary(insights_data)
        return {} unless insights_data.present?

        {
          total_customers_analyzed: insights_data.dig('executive_summary', 'period_overview', 'total_customers_analyzed'),
          total_revenue_processed: insights_data.dig('executive_summary', 'period_overview', 'total_revenue'),
          key_metrics: insights_data.dig('executive_summary', 'customer_highlights'),
          recommendations_count: insights_data['business_recommendations']&.length || 0,
          alerts_count: insights_data['performance_alerts']&.length || 0
        }
      end

      def extract_dashboard_summary(dashboard_data)
        return {} unless dashboard_data.present?

        {
          dashboards_updated: dashboard_data['dashboards_updated'] || [],
          update_status: dashboard_data['status'],
          last_updated: dashboard_data['updated_at']
        }
      end

      def extract_period_info(insights_data)
        {
          start_date: task.context.dig('date_range', 'start_date'),
          end_date: task.context.dig('date_range', 'end_date'),
          processing_completed_at: Time.current.iso8601
        }
      end

      def determine_target_team(recommendation_type)
        case recommendation_type
        when 'customer_retention'
          'customer-success'
        when 'inventory_optimization'
          'operations'
        when 'pricing_strategy'
          'revenue'
        when 'marketing_campaign'
          'marketing'
        else
          'data-team'
        end
      end

      def should_send_summary_email?(insights_data)
        # Business logic: Send email if we have meaningful insights
        return false unless insights_data.present?

        executive_summary = insights_data['executive_summary']
        return false unless executive_summary.present?

        # Send if we have customer data or significant revenue
        customers_analyzed = executive_summary.dig('period_overview', 'total_customers_analyzed') || 0
        revenue_processed = executive_summary.dig('period_overview', 'total_revenue') || 0

        customers_analyzed > 0 || revenue_processed > 0
      end

      def determine_email_recipients(insights_data)
        # Business logic: Determine who should receive the summary
        base_recipients = ['executives@company.com', 'data-team@company.com']

        # Add specific recipients based on alerts and recommendations
        additional_recipients = []

        if insights_data['performance_alerts']&.any? { |a| a['severity'] == 'critical' }
          additional_recipients << 'operations@company.com'
        end

        if insights_data['business_recommendations']&.any? { |r| r['type'] == 'customer_retention' }
          additional_recipients << 'customer-success@company.com'
        end

        (base_recipients + additional_recipients).uniq
      end

      def log_structured_info(message, **context)
        log_structured(:info, message, step_name: 'send_notifications', **context)
      end
    end
  end
end
