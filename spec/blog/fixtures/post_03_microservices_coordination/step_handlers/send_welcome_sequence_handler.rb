module UserManagement
  module StepHandlers
    class SendWelcomeSequenceHandler < ApiBaseHandler
      def process(task, sequence, step)
        # Store context for base class
        super(task, sequence, step)
        
        user_results = step_results(sequence, 'create_user_account')
        billing_results = step_results(sequence, 'setup_billing_profile')
        preferences_results = step_results(sequence, 'initialize_preferences')
        
        user_id = user_results['user_id']
        email = user_results['email'] || task.context['email']
        
        if user_id.blank? || email.blank?
          raise StandardError, "Cannot send welcome sequence without user_id and email"
        end
        
        notification_data = build_notification_data(task.context, user_results, billing_results, preferences_results)
        service_url = notification_service_url
        
        log_structured_info("Sending welcome sequence", {
          user_id: user_id,
          email: email,
          plan: task.context['plan']
        })
        
        response = with_circuit_breaker('notification_service') do
          start_time = Time.current
          
          log_api_call(:post, "#{service_url}/notifications/welcome", timeout: 15)
          
          # Use Tasker's Faraday connection
          response = connection.post("#{service_url}/notifications/welcome") do |req|
            req.body = notification_data.to_json
            req.headers.merge!(enhanced_default_headers)
          end
          
          duration_ms = ((Time.current - start_time) * 1000).to_i
          log_api_response(:post, "#{service_url}/notifications/welcome", response, duration_ms)
          
          response
        end
        
        case response.status
        when 200, 201
          # Welcome sequence initiated successfully
          notification_response = response.body
          log_structured_info("Welcome sequence sent successfully", {
            user_id: user_id,
            notification_id: notification_response['id'],
            delivery_method: notification_response['delivery_method']
          })
          
          {
            notification_id: notification_response['id'],
            user_id: user_id,
            email: email,
            delivery_method: notification_response['delivery_method'],
            scheduled_delivery: notification_response['scheduled_at'],
            status: notification_response['status'],
            correlation_id: correlation_id,
            service_response_time: response.headers['x-response-time']
          }
          
        when 202
          # Accepted - queued for delivery
          notification_response = response.body
          log_structured_info("Welcome sequence queued for delivery", {
            user_id: user_id,
            queue_id: notification_response['queue_id']
          })
          
          {
            notification_id: notification_response['queue_id'],
            user_id: user_id,
            email: email,
            delivery_method: 'queued',
            status: 'queued',
            estimated_delivery: notification_response['estimated_delivery'],
            correlation_id: correlation_id
          }
          
        when 409
          # Duplicate notification - welcome already sent
          log_structured_info("Welcome sequence already sent to user", {
            user_id: user_id,
            email: email
          })
          
          existing_notification = get_existing_notification(user_id, 'welcome')
          
          {
            notification_id: existing_notification&.dig('id') || "duplicate_#{user_id}",
            user_id: user_id,
            email: email,
            status: 'already_sent',
            original_sent_at: existing_notification&.dig('sent_at'),
            correlation_id: correlation_id
          }
          
        when 422
          # Validation error - invalid email or user data
          errors = response.body['errors'] || response.body['message']
          raise StandardError, "Invalid notification data: #{errors}"
          
        when 429
          # Rate limited - too many notifications
          retry_after = response.headers['retry-after']&.to_i || 60
          log_structured_info("Rate limited by notification service", {
            retry_after: retry_after,
            user_id: user_id
          })
          
          raise Tasker::RetryableError.new(
            "Notification service rate limited. Retry after #{retry_after} seconds",
            retry_after: retry_after
          )
          
        else
          # Let base handler deal with other responses
          handle_microservice_response(response, 'notification_service')
        end
        
      rescue CircuitOpenError => e
        # Circuit breaker is open - notification service is down
        log_structured_error("Circuit breaker open for notification service", {
          error: e.message,
          service: 'notification_service',
          user_id: user_id
        })
        
        # Store notification for later delivery
        stored_notification = store_for_later_delivery(notification_data)
        
        {
          notification_id: stored_notification[:id],
          user_id: user_id,
          email: email,
          status: 'stored_for_retry',
          delivery_method: 'deferred',
          error: 'notification_service_unavailable',
          will_retry_at: stored_notification[:retry_at],
          correlation_id: correlation_id
        }
        
      rescue => e
        log_structured_error("Failed to send welcome sequence", {
          error: e.message,
          error_class: e.class.name,
          user_id: user_id,
          email: email
        })
        raise
      end
      
      private
      
      def build_notification_data(context, user_results, billing_results, preferences_results)
        # Gather personalization data from all previous steps
        user_name = user_results['email'] ? user_results['email'].split('@').first.capitalize : 'New User'
        plan = billing_results['plan'] || context['plan'] || 'free'
        
        # Check if user has opted into marketing communications
        marketing_consent = preferences_results['settings']&.dig('privacy', 'marketing') || 
                           context['marketing_consent'] || false
        
        {
          recipient: {
            user_id: user_results['user_id'],
            email: user_results['email'] || context['email'],
            name: context['name'] || user_name
          },
          template: determine_welcome_template(plan, context['source']),
          personalization: {
            user_name: context['name'] || user_name,
            plan: plan,
            source: context['source'] || 'web',
            company_name: context['company_name'],
            referral_code: context['referral_code'],
            features_available: get_plan_features(plan)
          },
          settings: {
            marketing_consent: marketing_consent,
            language: preferences_results['settings']&.dig('ui', 'language') || 'en',
            timezone: preferences_results['settings']&.dig('ui', 'timezone') || 'UTC'
          },
          delivery_options: {
            priority: plan == 'enterprise' ? 'high' : 'normal',
            track_opens: true,
            track_clicks: true,
            send_time: 'immediate'
          },
          metadata: {
            registration_source: context['source'] || 'web',
            correlation_id: correlation_id,
            registration_date: Time.current.iso8601
          }
        }
      end
      
      def determine_welcome_template(plan, source)
        case plan
        when 'enterprise'
          'welcome_enterprise'
        when 'pro'
          source == 'mobile' ? 'welcome_pro_mobile' : 'welcome_pro'
        else
          source == 'mobile' ? 'welcome_free_mobile' : 'welcome_free'
        end
      end
      
      def get_plan_features(plan)
        case plan
        when 'enterprise'
          ['unlimited_projects', 'priority_support', 'advanced_analytics', 'custom_integrations', 'dedicated_account_manager']
        when 'pro'
          ['unlimited_projects', 'priority_support', 'advanced_analytics']
        else
          ['basic_projects', 'community_support', 'basic_analytics']
        end
      end
      
      def get_existing_notification(user_id, notification_type)
        response = with_circuit_breaker('notification_service') do
          connection.get("#{notification_service_url}/notifications") do |req|
            req.params = { 
              user_id: user_id, 
              type: notification_type,
              limit: 1 
            }
            req.headers.merge!(enhanced_default_headers)
          end
        end
        
        if response.success?
          notifications = response.body['notifications'] || []
          notifications.first
        else
          nil
        end
      rescue => e
        log_structured_error("Failed to check existing notifications", {
          error: e.message,
          user_id: user_id,
          notification_type: notification_type
        })
        nil
      end
      
      def store_for_later_delivery(notification_data)
        # In a real implementation, this would store to a retry queue
        # For demo purposes, we'll simulate this
        retry_at = Time.current + get_handler_config('backoff_request_seconds', 60).seconds
        
        stored_id = "deferred_#{SecureRandom.hex(8)}"
        
        log_structured_info("Storing notification for later delivery", {
          stored_id: stored_id,
          retry_at: retry_at.iso8601,
          recipient: notification_data[:recipient][:email]
        })
        
        # In production, store in Redis/database retry queue
        # Redis.setex("notification_retry:#{stored_id}", 3600, notification_data.to_json)
        
        {
          id: stored_id,
          retry_at: retry_at.iso8601
        }
      end
      
      def get_handler_config(key, default_value)
        # Get configuration from step template handler_config
        step&.step_template&.handler_config&.dig(key) || default_value
      end
      
      def notification_service_url
        ENV.fetch('NOTIFICATION_SERVICE_URL', 'http://localhost:3004')
      end
      
      def log_structured_info(message, context = {})
        log_structured(:info, message, { step_name: 'send_welcome_sequence', service: 'notification_service' }.merge(context))
      end
      
      def log_structured_error(message, context = {})
        log_structured(:error, message, { step_name: 'send_welcome_sequence', service: 'notification_service' }.merge(context))
      end
    end
  end
end