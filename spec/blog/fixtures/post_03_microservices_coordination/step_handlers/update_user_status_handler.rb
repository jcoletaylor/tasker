module UserManagement
  module StepHandlers
    class UpdateUserStatusHandler < ApiBaseHandler
      def process(task, sequence, step)
        # Store context for base class
        super(task, sequence, step)
        
        user_results = step_results(sequence, 'create_user_account')
        user_id = user_results['user_id']
        
        if user_id.blank?
          raise StandardError, "Cannot update user status without user_id"
        end
        
        # Gather completion data from all previous steps
        billing_results = step_results(sequence, 'setup_billing_profile')
        preferences_results = step_results(sequence, 'initialize_preferences')
        notification_results = step_results(sequence, 'send_welcome_sequence')
        
        status_data = build_completion_status(task.context, billing_results, preferences_results, notification_results)
        service_url = user_service_url
        
        log_structured_info("Updating user registration status to complete", {
          user_id: user_id,
          billing_complete: billing_results.present?,
          preferences_complete: preferences_results.present?,
          notification_sent: notification_results.present?
        })
        
        response = with_circuit_breaker('user_service') do
          start_time = Time.current
          
          log_api_call(:patch, "#{service_url}/users/#{user_id}/status", timeout: 10)
          
          # Use Tasker's Faraday connection
          response = connection.patch("#{service_url}/users/#{user_id}/status") do |req|
            req.body = status_data.to_json
            req.headers.merge!(enhanced_default_headers)
          end
          
          duration_ms = ((Time.current - start_time) * 1000).to_i
          log_api_response(:patch, "#{service_url}/users/#{user_id}/status", response, duration_ms)
          
          response
        end
        
        case response.status
        when 200
          # Status updated successfully
          user_data = response.body
          log_structured_info("User registration marked as complete", {
            user_id: user_id,
            registration_status: user_data['registration_status'],
            completed_at: user_data['registration_completed_at']
          })
          
          {
            user_id: user_id,
            registration_status: user_data['registration_status'],
            registration_completed_at: user_data['registration_completed_at'],
            billing_profile_id: billing_results['billing_profile_id'],
            preferences_id: preferences_results['preferences_id'],
            notification_id: notification_results['notification_id'],
            correlation_id: correlation_id,
            service_response_time: response.headers['x-response-time']
          }
          
        when 404
          # User not found - this shouldn't happen if create_user_account succeeded
          raise StandardError, "User #{user_id} not found when updating status"
          
        when 409
          # User already marked as complete - handle idempotency
          log_structured_info("User registration already marked complete", {
            user_id: user_id
          })
          
          existing_user = get_user_details(user_id)
          
          {
            user_id: user_id,
            registration_status: existing_user&.dig('registration_status') || 'complete',
            registration_completed_at: existing_user&.dig('registration_completed_at'),
            billing_profile_id: billing_results['billing_profile_id'],
            preferences_id: preferences_results['preferences_id'],
            notification_id: notification_results['notification_id'],
            correlation_id: correlation_id,
            status: 'already_complete'
          }
          
        when 422
          # Validation error - invalid status data
          errors = response.body['errors'] || response.body['message']
          raise StandardError, "Invalid status update data: #{errors}"
          
        else
          # Let base handler deal with other responses
          handle_microservice_response(response, 'user_service')
        end
        
      rescue CircuitOpenError => e
        # Circuit breaker is open - user service is down
        log_structured_error("Circuit breaker open for user service", {
          error: e.message,
          service: 'user_service',
          user_id: user_id
        })
        
        # This is a critical step - we need the user marked as complete
        # But we can return success data based on step results
        log_structured_info("User service unavailable, registration functionally complete", {
          user_id: user_id
        })
        
        {
          user_id: user_id,
          registration_status: 'functionally_complete',
          billing_profile_id: billing_results['billing_profile_id'],
          preferences_id: preferences_results['preferences_id'],
          notification_id: notification_results['notification_id'],
          error: 'user_service_unavailable',
          correlation_id: correlation_id,
          note: 'User registration is functionally complete but status update pending'
        }
        
      rescue => e
        log_structured_error("Failed to update user status", {
          error: e.message,
          error_class: e.class.name,
          user_id: user_id
        })
        raise
      end
      
      private
      
      def build_completion_status(context, billing_results, preferences_results, notification_results)
        {
          registration_status: 'complete',
          registration_completed_at: Time.current.iso8601,
          completion_details: {
            billing_setup: billing_results.present?,
            preferences_initialized: preferences_results.present?,
            welcome_notification_sent: notification_results.present?,
            plan: context['plan'] || 'free',
            source: context['source'] || 'web'
          },
          metadata: {
            correlation_id: correlation_id,
            completed_steps: [
              billing_results.present? ? 'billing' : nil,
              preferences_results.present? ? 'preferences' : nil,
              notification_results.present? ? 'notification' : nil
            ].compact,
            any_degraded_services: [
              billing_results&.dig('degraded'),
              preferences_results&.dig('degraded'),
              notification_results&.dig('error')
            ].any?
          }
        }
      end
      
      def get_user_details(user_id)
        response = with_circuit_breaker('user_service') do
          connection.get("#{user_service_url}/users/#{user_id}") do |req|
            req.headers.merge!(enhanced_default_headers)
          end
        end
        
        response.success? ? response.body : nil
      rescue => e
        log_structured_error("Failed to get user details", {
          error: e.message,
          user_id: user_id
        })
        nil
      end
      
      def user_service_url
        ENV.fetch('USER_SERVICE_URL', 'http://localhost:3001')
      end
      
      def log_structured_info(message, context = {})
        log_structured(:info, message, { step_name: 'update_user_status', service: 'user_service' }.merge(context))
      end
      
      def log_structured_error(message, context = {})
        log_structured(:error, message, { step_name: 'update_user_status', service: 'user_service' }.merge(context))
      end
    end
  end
end