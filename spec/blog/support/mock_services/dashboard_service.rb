# frozen_string_literal: true

# Mock Dashboard Service for Post 02: Data Pipeline Resilience
# Simulates dashboard updates and notification delivery

class MockDashboardService < BaseMockService
  # Error classes that step handlers expect to catch
  class TimeoutError < StandardError; end
  class ConnectionError < StandardError; end
  class AuthenticationError < StandardError; end
  class RateLimitedError < StandardError; end
  class InvalidChannelError < StandardError; end

  # Update executive dashboard with new metrics
  def self.update_dashboard(insights:, **)
    instance = new
    instance.update_dashboard_call(insights: insights, **)
  end

  # Send notifications to stakeholders
  def self.send_notifications(notification_channels:, insights:, **)
    instance = new
    instance.send_notifications_call(notification_channels: notification_channels, insights: insights, **)
  end

  # Send email reports (additional notification method)
  def self.send_email_report(recipients:, insights:, **)
    instance = new
    instance.send_email_report_call(recipients: recipients, insights: insights, **)
  end

  # Instance methods for actual processing
  def update_dashboard_call(insights:, **options)
    log_call(:update_dashboard, {
               insights_keys: insights&.keys || [],
               options: options
             })

    # Simulate dashboard update
    dashboard_update = {
      dashboard_id: "executive_dashboard_#{Date.current.strftime('%Y_%m')}",
      updated_sections: %w[
        customer_metrics
        product_performance
        revenue_insights
        segment_analysis
      ],
      last_updated: Time.current.iso8601,
      data_freshness: Time.current.iso8601
    }

    default_response = {
      status: 'success',
      data: dashboard_update,
      metadata: {
        dashboard_url: 'https://dashboard.company.com/executive',
        update_time: Time.current.iso8601
      }
    }

    handle_response(:update_dashboard, default_response)
  end

  def send_notifications_call(notification_channels:, insights:, **options)
    log_call(:send_notifications, {
               channels: notification_channels,
               insights_summary: insights&.keys || [],
               options: options
             })

    # Simulate sending notifications to each channel
    notifications_sent = notification_channels.map do |channel|
      {
        channel: channel,
        message_id: "msg_#{SecureRandom.hex(8)}",
        status: 'delivered',
        sent_at: Time.current.iso8601
      }
    end

    default_response = {
      status: 'success',
      data: {
        notifications: notifications_sent,
        summary: generate_notification_summary(insights)
      },
      metadata: {
        total_channels: notification_channels.length,
        delivery_time: Time.current.iso8601
      }
    }

    handle_response(:send_notifications, default_response)
  end

  def send_email_report_call(recipients:, insights:, **options)
    log_call(:send_email_report, {
               recipients: recipients,
               insights_summary: insights&.keys || [],
               options: options
             })

    # Simulate email delivery
    emails_sent = recipients.map do |recipient|
      {
        recipient: recipient,
        message_id: "email_#{SecureRandom.hex(10)}",
        subject: "Analytics Pipeline Report - #{Date.current.strftime('%B %d, %Y')}",
        status: 'delivered',
        sent_at: Time.current.iso8601
      }
    end

    default_response = {
      status: 'success',
      data: {
        emails: emails_sent,
        report_url: "https://reports.company.com/analytics/#{Date.current.strftime('%Y-%m-%d')}"
      },
      metadata: {
        total_recipients: recipients.length,
        delivery_time: Time.current.iso8601
      }
    }

    handle_response(:send_email_report, default_response)
  end

  private

  def generate_notification_summary(insights)
    return 'No insights available' unless insights

    summary_parts = []

    if insights[:top_customers]
      top_customer_revenue = insights[:top_customers].sum { |c| c[:total_revenue] }
      summary_parts << "Top 3 customers generated $#{top_customer_revenue.round(2)} in revenue"
    end

    if insights[:top_products]
      top_product_revenue = insights[:top_products].sum { |p| p[:total_revenue] }
      summary_parts << "Top 3 products generated $#{top_product_revenue.round(2)} in revenue"
    end

    if insights[:segment_analysis]
      premium_count = insights[:segment_analysis][:premium_customers]
      standard_count = insights[:segment_analysis][:standard_customers]
      summary_parts << "Customer segments: #{premium_count} premium, #{standard_count} standard"
    end

    "#{summary_parts.join('. ')}."
  end
end
