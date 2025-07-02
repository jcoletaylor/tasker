module UserManagement
  module StepHandlers
    class CreateUserAccountHandler < ApiBaseHandler
      def process(task, sequence, step)
        # Store context for base class
        super(task, sequence, step)
        
        user_data = extract_user_data(task.context)
        service_url = user_service_url
        
        log_structured_info("Creating user account", {
          email: user_data[:email],
          plan: task.context['plan']
        })
        
        start_time = Time.current
        
        log_api_call(:post, "#{service_url}/users", timeout: 30)
        
        # Use Tasker's Faraday connection - circuit breaker logic handled by Tasker's retry system
        response = connection.post("#{service_url}/users") do |req|
          req.body = user_data.to_json
          req.headers.merge!(enhanced_default_headers)
        end
        
        duration_ms = ((Time.current - start_time) * 1000).to_i
        log_api_response(:post, "#{service_url}/users", response, duration_ms)
        
        case response.status
        when 201
          # User created successfully
          user_response = response.body
          log_structured_info("User account created successfully", {
            user_id: user_response['id'],
            email: user_response['email']
          })
          
          {
            user_id: user_response['id'],
            email: user_response['email'],
            created_at: user_response['created_at'],
            correlation_id: correlation_id,
            service_response_time: response.headers['x-response-time'],
            status: 'created'
          }
          
        when 409
          # User already exists - check if it's the same user
          log_structured_info("User already exists, checking for idempotency", {
            email: user_data[:email]
          })
          
          existing_user = get_existing_user(user_data[:email])
          
          if existing_user && user_matches?(existing_user, user_data)
            log_structured_info("Existing user matches, treating as idempotent success", {
              user_id: existing_user['id']
            })
            
            {
              user_id: existing_user['id'],
              email: existing_user['email'],
              created_at: existing_user['created_at'],
              correlation_id: correlation_id,
              status: 'already_exists'
            }
          else
            raise StandardError, "User with email #{user_data[:email]} already exists with different data"
          end
          
        else
          # Let Tasker's enhanced error handling manage circuit breaker logic
          handle_microservice_response(response, 'user_service')
        end
        
      rescue => e
        log_structured_error("Failed to create user account", {
          error: e.message,
          error_class: e.class.name,
          email: user_data[:email]
        })
        raise
      end
      
      private
      
      def extract_user_data(context)
        {
          email: context['email'],
          name: context['name'],
          phone: context['phone'],
          plan: context['plan'] || 'free',
          marketing_consent: context['marketing_consent'] || false,
          referral_code: context['referral_code'],
          source: context['source'] || 'web'
        }.compact
      end
      
      def get_existing_user(email)
        # Tasker's retry system will handle failures automatically
        response = connection.get("#{user_service_url}/users") do |req|
          req.params = { email: email }
          req.headers.merge!(enhanced_default_headers)
        end
        
        response.success? ? response.body : nil
      rescue Tasker::PermanentError => e
        # Don't retry permanent failures (like 404s)
        log_structured_error("Permanent error checking existing user", {
          error: e.message,
          email: email
        })
        nil
      rescue => e
        # Re-raise other errors for Tasker's retry system to handle
        log_structured_error("Failed to check existing user", {
          error: e.message,
          email: email
        })
        raise
      end
      
      def user_matches?(existing_user, new_user_data)
        # Check if core attributes match for idempotency
        existing_user &&
          existing_user['email'] == new_user_data[:email] &&
          existing_user['name'] == new_user_data[:name] &&
          existing_user['plan'] == new_user_data[:plan]
      end
      
      def user_service_url
        ENV.fetch('USER_SERVICE_URL', 'http://localhost:3001')
      end
      
      def log_structured_info(message, context = {})
        log_structured(:info, message, { step_name: 'create_user_account', service: 'user_service' }.merge(context))
      end
      
      def log_structured_error(message, context = {})
        log_structured(:error, message, { step_name: 'create_user_account', service: 'user_service' }.merge(context))
      end
    end
  end
end