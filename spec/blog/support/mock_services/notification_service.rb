# frozen_string_literal: true

module BlogExamples
  module MockServices
    class MockNotificationService < BaseMockService
      def initialize
        super
        @service_name = 'notification_service'
        @notifications = {}
        @user_notifications = {}
        @next_notification_id = 1
        @rate_limit_counts = {}
      end

      # POST /notifications/welcome - Send welcome sequence
      def send_welcome_sequence(user_id, template_data)
        log_call(:send_welcome_sequence, { user_id: user_id, template_data: template_data })

        check_failure!(:send_welcome_sequence)
        check_rate_limit!(user_id)

        plan = template_data[:plan] || template_data['plan'] || 'free'
        name = template_data[:name] || template_data['name'] || 'User'

        # Select welcome template based on plan
        welcome_template = case plan
                           when 'enterprise'
                             'enterprise_welcome'
                           when 'pro'
                             'pro_welcome'
                           else
                             'standard_welcome'
                           end

        # Create welcome sequence notifications
        sequence_notifications = []

        # Immediate welcome
        welcome_notification = create_notification(user_id, {
                                                     type: 'welcome',
                                                     template: welcome_template,
                                                     subject: "Welcome to our platform, #{name}!",
                                                     content: generate_welcome_content(plan, name),
                                                     priority: 'high',
                                                     scheduled_for: Time.current.iso8601
                                                   })
        sequence_notifications << welcome_notification

        # Follow-up notifications based on plan
        if plan == 'enterprise'
          # Enterprise gets onboarding call scheduling
          onboarding_notification = create_notification(user_id, {
                                                          type: 'onboarding',
                                                          template: 'enterprise_onboarding',
                                                          subject: 'Schedule your enterprise onboarding call',
                                                          content: 'Our enterprise team is ready to help you get started.',
                                                          priority: 'high',
                                                          scheduled_for: 1.hour.from_now.iso8601
                                                        })
          sequence_notifications << onboarding_notification
        elsif plan == 'pro'
          # Pro gets feature tour
          tour_notification = create_notification(user_id, {
                                                    type: 'feature_tour',
                                                    template: 'pro_feature_tour',
                                                    subject: 'Discover your Pro features',
                                                    content: 'Learn about the advanced features available in your Pro plan.',
                                                    priority: 'medium',
                                                    scheduled_for: 2.hours.from_now.iso8601
                                                  })
          sequence_notifications << tour_notification
        end

        # Tips notification for all plans (after 24 hours)
        tips_notification = create_notification(user_id, {
                                                  type: 'tips',
                                                  template: 'getting_started_tips',
                                                  subject: 'Getting started tips',
                                                  content: 'Here are some tips to help you make the most of our platform.',
                                                  priority: 'low',
                                                  scheduled_for: 24.hours.from_now.iso8601
                                                })
        sequence_notifications << tips_notification

        response_data = {
          sequence_id: generate_id('seq'),
          user_id: user_id,
          template: welcome_template,
          notifications_scheduled: sequence_notifications.length,
          notifications: sequence_notifications.map do |n|
            { id: n[:id], type: n[:type], scheduled_for: n[:scheduled_for] }
          end,
          created_at: Time.current.iso8601
        }

        mock_http_response(201, response_data)
      end

      # POST /notifications/single - Send single notification
      def send_notification(user_id, notification_data)
        log_call(:send_notification, { user_id: user_id, notification_data: notification_data })

        check_failure!(:send_notification)
        check_rate_limit!(user_id)

        notification = create_notification(user_id, notification_data)

        mock_http_response(201, notification)
      end

      # GET /notifications/:user_id - Get user notifications
      def get_user_notifications(user_id)
        log_call(:get_user_notifications, { user_id: user_id })

        check_failure!(:get_user_notifications)

        user_notifications = @user_notifications[user_id] || []
        notifications = user_notifications.filter_map { |id| @notifications[id] }

        response_data = {
          user_id: user_id,
          total_count: notifications.length,
          unread_count: notifications.count { |n| !n[:read] },
          notifications: notifications.sort_by { |n| n[:created_at] }.reverse
        }

        mock_http_response(200, response_data)
      end

      # GET /notifications/:id - Get specific notification
      def get_notification(notification_id)
        log_call(:get_notification, { notification_id: notification_id })

        check_failure!(:get_notification)

        notification = @notifications[notification_id.to_i]

        if notification
          mock_http_response(200, notification)
        else
          mock_http_response(404, { error: 'Notification not found', notification_id: notification_id })
        end
      end

      # Reset service state
      def reset!
        @notifications.clear
        @user_notifications.clear
        @next_notification_id = 1
        @rate_limit_counts.clear
      end

      # Configure failures for testing
      def configure_failures(method, options = {})
        self.class.stub_failure(method, StandardError, options[:message], fail_count: options[:fail_count])
      end

      private

      def create_notification(user_id, notification_data)
        notification = {
          id: @next_notification_id,
          user_id: user_id,
          type: notification_data[:type] || notification_data['type'] || 'general',
          template: notification_data[:template] || notification_data['template'],
          subject: notification_data[:subject] || notification_data['subject'],
          content: notification_data[:content] || notification_data['content'],
          priority: notification_data[:priority] || notification_data['priority'] || 'medium',
          channel: notification_data[:channel] || notification_data['channel'] || 'email',
          scheduled_for: notification_data[:scheduled_for] || notification_data['scheduled_for'] || Time.current.iso8601,
          sent_at: Time.current.iso8601,
          read: false,
          created_at: Time.current.iso8601,
          updated_at: Time.current.iso8601
        }

        @notifications[@next_notification_id] = notification
        @user_notifications[user_id] ||= []
        @user_notifications[user_id] << @next_notification_id
        @next_notification_id += 1

        notification
      end

      def generate_welcome_content(plan, name)
        case plan
        when 'enterprise'
          "Welcome #{name}! Your enterprise account is ready. Our team will contact you shortly to schedule your onboarding session."
        when 'pro'
          "Welcome #{name}! Your Pro account gives you access to advanced features. Check out our feature tour to get started."
        else
          "Welcome #{name}! Thanks for joining us. We're excited to help you get started."
        end
      end

      def check_rate_limit!(user_id)
        # Simple rate limiting: max 10 notifications per minute per user
        current_minute = Time.current.strftime('%Y-%m-%d %H:%M')
        rate_key = "#{user_id}:#{current_minute}"

        @rate_limit_counts[rate_key] ||= 0
        @rate_limit_counts[rate_key] += 1

        return unless @rate_limit_counts[rate_key] > 10

        # Return rate limit error
        raise_rate_limit_error
      end

      def raise_rate_limit_error
        error_response = mock_http_response(429, {
                                              error: 'Rate limit exceeded',
                                              message: 'Too many notification requests. Please try again later.',
                                              retry_after: 60
                                            })
        # Add retry-after header
        error_response.headers['retry-after'] = '60'
        raise error_response
      end

      def check_failure!(method)
        # Let the base class handle failure simulation
        handle_response(method, {})
      end

      def mock_http_response(status, body)
        MockHttpResponse.new(status, body, {
                               'content-type' => 'application/json',
                               'x-response-time' => "#{rand(20..100)}ms",
                               'x-service' => 'notification-service',
                               'x-version' => '3.2.1'
                             })
      end
    end
  end
end
