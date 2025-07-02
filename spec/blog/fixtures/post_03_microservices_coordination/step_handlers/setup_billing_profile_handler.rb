module UserManagement
  module StepHandlers
    class SetupBillingProfileHandler < ApiBaseHandler
      def process(task, sequence, step)
        # Store context for base class
        super(task, sequence, step)
        
        user_results = step_results(sequence, 'create_user_account')
        user_id = user_results['user_id']
        
        if user_id.blank?
          raise StandardError, "Cannot setup billing without user_id"
        end
        
        billing_data = extract_billing_data(task.context, user_id)
        service_url = billing_service_url
        
        log_structured_info("Setting up billing profile", {
          user_id: user_id,
          plan: billing_data[:plan]
        })
        
        response = with_circuit_breaker('billing_service') do
          start_time = Time.current
          
          log_api_call(:post, "#{service_url}/profiles", timeout: 30)
          
          # Use Tasker's Faraday connection
          response = connection.post("#{service_url}/profiles") do |req|
            req.body = billing_data.to_json
            req.headers.merge!(enhanced_default_headers)
          end
          
          duration_ms = ((Time.current - start_time) * 1000).to_i
          log_api_response(:post, "#{service_url}/profiles", response, duration_ms)
          
          response
        end
        
        case response.status
        when 201
          # Billing profile created
          profile_data = response.body
          log_structured_info("Billing profile created successfully", {
            user_id: user_id,
            billing_id: profile_data['id'],
            plan: profile_data['plan']
          })
          
          {
            billing_id: profile_data['id'],
            user_id: user_id,
            plan: profile_data['plan'],
            status: profile_data['status'],
            trial_ends_at: profile_data['trial_ends_at'],
            created_at: profile_data['created_at'],
            correlation_id: correlation_id,
            service_response_time: response.headers['x-response-time']
          }
          
        when 409
          # Billing profile already exists
          log_structured_info("Billing profile already exists, checking status", {
            user_id: user_id
          })
          
          existing_profile = get_existing_profile(user_id)
          
          if existing_profile && profile_matches?(existing_profile, billing_data)
            log_structured_info("Existing profile matches, treating as idempotent success", {
              user_id: user_id,
              billing_id: existing_profile['id']
            })
            
            {
              billing_id: existing_profile['id'],
              user_id: user_id,
              plan: existing_profile['plan'],
              status: existing_profile['status'],
              trial_ends_at: existing_profile['trial_ends_at'],
              created_at: existing_profile['created_at'],
              correlation_id: correlation_id,
              already_exists: true
            }
          else
            # Different plan requested - this might be an upgrade/downgrade
            raise StandardError, "Billing profile exists with different plan. Current: #{existing_profile['plan']}, Requested: #{billing_data[:plan]}"
          end
          
        when 402
          # Payment required - for paid plans
          payment_details = response.body
          raise StandardError, "Payment required for plan #{billing_data[:plan]}. Payment URL: #{payment_details['payment_url']}"
          
        when 422
          # Validation error
          errors = response.body['errors'] || response.body['message']
          raise StandardError, "Invalid billing data: #{errors}"
          
        else
          # Let base handler deal with other responses
          handle_microservice_response(response, 'billing_service')
        end
        
      rescue CircuitOpenError => e
        # Circuit breaker is open - billing service is down
        log_structured_error("Circuit breaker open for billing service", {
          error: e.message,
          service: 'billing_service'
        })
        
        # For free plans, we might want to continue without billing
        if task.context['plan'] == 'free'
          log_structured_info("Billing service down but user is on free plan, continuing with degraded service", {
            user_id: user_id
          })
          
          {
            billing_id: nil,
            user_id: user_id,
            plan: 'free',
            status: 'pending_setup',
            degraded: true,
            error: 'billing_service_unavailable',
            correlation_id: correlation_id
          }
        else
          raise Tasker::RetryableError.new(e.message, retry_after: 120)  # Longer retry for billing
        end
        
      rescue => e
        log_structured_error("Failed to setup billing profile", {
          error: e.message,
          error_class: e.class.name,
          user_id: user_id
        })
        raise
      end
      
      private
      
      def extract_billing_data(context, user_id)
        {
          user_id: user_id,
          plan: context['plan'] || 'free',
          payment_method: context['payment_method'],
          billing_email: context['billing_email'] || context['email'],
          company_name: context['company_name'],
          tax_id: context['tax_id'],
          billing_address: context['billing_address']
        }.compact
      end
      
      def get_existing_profile(user_id)
        response = with_circuit_breaker('billing_service') do
          connection.get("#{billing_service_url}/profiles/#{user_id}") do |req|
            req.headers.merge!(enhanced_default_headers)
          end
        end
        
        response.success? ? response.body : nil
      rescue => e
        log_structured_error("Failed to check existing billing profile", {
          error: e.message,
          user_id: user_id
        })
        nil
      end
      
      def profile_matches?(existing_profile, new_billing_data)
        existing_profile &&
          existing_profile['user_id'].to_s == new_billing_data[:user_id].to_s &&
          existing_profile['plan'] == new_billing_data[:plan]
      end
      
      def billing_service_url
        ENV.fetch('BILLING_SERVICE_URL', 'http://localhost:3002')
      end
      
      def log_structured_info(message, context = {})
        log_structured(:info, message, { step_name: 'setup_billing_profile', service: 'billing_service' }.merge(context))
      end
      
      def log_structured_error(message, context = {})
        log_structured(:error, message, { step_name: 'setup_billing_profile', service: 'billing_service' }.merge(context))
      end
    end
  end
end