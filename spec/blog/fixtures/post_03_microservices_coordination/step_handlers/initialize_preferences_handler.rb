module UserManagement
  module StepHandlers
    class InitializePreferencesHandler < ApiBaseHandler
      def process(task, sequence, step)
        # Store context for base class
        super(task, sequence, step)
        
        user_results = step_results(sequence, 'create_user_account')
        user_id = user_results['user_id']
        
        if user_id.blank?
          raise StandardError, "Cannot initialize preferences without user_id"
        end
        
        preferences_data = extract_preferences_data(task.context, user_id)
        service_url = preferences_service_url
        
        log_structured_info("Initializing user preferences", {
          user_id: user_id,
          source: task.context['source']
        })
        
        response = with_circuit_breaker('preferences_service') do
          start_time = Time.current
          
          log_api_call(:post, "#{service_url}/preferences", timeout: 20)
          
          # Use Tasker's Faraday connection
          response = connection.post("#{service_url}/preferences") do |req|
            req.body = preferences_data.to_json
            req.headers.merge!(enhanced_default_headers)
          end
          
          duration_ms = ((Time.current - start_time) * 1000).to_i
          log_api_response(:post, "#{service_url}/preferences", response, duration_ms)
          
          response
        end
        
        case response.status
        when 201
          # Preferences created successfully
          prefs_data = response.body
          log_structured_info("Preferences initialized successfully", {
            user_id: user_id,
            preferences_id: prefs_data['id']
          })
          
          {
            preferences_id: prefs_data['id'],
            user_id: user_id,
            settings: prefs_data['settings'],
            created_at: prefs_data['created_at'],
            correlation_id: correlation_id,
            service_response_time: response.headers['x-response-time']
          }
          
        when 409
          # Preferences already exist - handle idempotency
          log_structured_info("Preferences already exist, checking compatibility", {
            user_id: user_id
          })
          
          existing_prefs = get_existing_preferences(user_id)
          
          if existing_prefs && preferences_compatible?(existing_prefs, preferences_data)
            log_structured_info("Existing preferences compatible, treating as idempotent success", {
              user_id: user_id,
              preferences_id: existing_prefs['id']
            })
            
            {
              preferences_id: existing_prefs['id'],
              user_id: user_id,
              settings: existing_prefs['settings'],
              created_at: existing_prefs['created_at'],
              correlation_id: correlation_id,
              status: 'already_exists'
            }
          else
            # Preferences exist but with different settings - this could be an update scenario
            log_structured_info("Preferences exist with different settings, updating", {
              user_id: user_id
            })
            
            updated_prefs = update_existing_preferences(user_id, preferences_data)
            {
              preferences_id: updated_prefs['id'],
              user_id: user_id,
              settings: updated_prefs['settings'],
              updated_at: updated_prefs['updated_at'],
              correlation_id: correlation_id,
              status: 'updated'
            }
          end
          
        when 422
          # Validation error
          errors = response.body['errors'] || response.body['message']
          raise StandardError, "Invalid preferences data: #{errors}"
          
        else
          # Let base handler deal with other responses
          handle_microservice_response(response, 'preferences_service')
        end
        
      rescue CircuitOpenError => e
        # Circuit breaker is open - preferences service is down
        log_structured_error("Circuit breaker open for preferences service", {
          error: e.message,
          service: 'preferences_service'
        })
        
        # Preferences are non-critical - continue with defaults
        log_structured_info("Preferences service unavailable, using default settings", {
          user_id: user_id
        })
        
        {
          preferences_id: nil,
          user_id: user_id,
          settings: default_preferences_settings(task.context),
          degraded: true,
          error: 'preferences_service_unavailable',
          correlation_id: correlation_id
        }
        
      rescue => e
        log_structured_error("Failed to initialize preferences", {
          error: e.message,
          error_class: e.class.name,
          user_id: user_id
        })
        raise
      end
      
      private
      
      def extract_preferences_data(context, user_id)
        {
          user_id: user_id,
          settings: {
            notifications: {
              email: context['marketing_consent'] || false,
              push: false, # Default to conservative settings
              sms: false
            },
            privacy: {
              data_sharing: false,
              analytics: true,
              marketing: context['marketing_consent'] || false
            },
            ui: {
              theme: 'light',
              language: 'en',
              timezone: 'UTC'
            },
            features: {
              newsletter: context['marketing_consent'] || false,
              product_updates: true,
              security_alerts: true
            }
          },
          source: context['source'] || 'web',
          plan: context['plan'] || 'free'
        }
      end
      
      def get_existing_preferences(user_id)
        response = with_circuit_breaker('preferences_service') do
          connection.get("#{preferences_service_url}/preferences/#{user_id}") do |req|
            req.headers.merge!(enhanced_default_headers)
          end
        end
        
        response.success? ? response.body : nil
      rescue => e
        log_structured_error("Failed to check existing preferences", {
          error: e.message,
          user_id: user_id
        })
        nil
      end
      
      def preferences_compatible?(existing_prefs, new_prefs_data)
        # Check if the core preferences match
        existing_settings = existing_prefs['settings'] || {}
        new_settings = new_prefs_data[:settings] || {}
        
        # Compare key privacy and notification settings
        existing_marketing = existing_settings.dig('privacy', 'marketing')
        new_marketing = new_settings.dig(:privacy, :marketing)
        
        existing_email = existing_settings.dig('notifications', 'email')
        new_email = new_settings.dig(:notifications, :email)
        
        existing_marketing == new_marketing && existing_email == new_email
      end
      
      def update_existing_preferences(user_id, preferences_data)
        response = with_circuit_breaker('preferences_service') do
          connection.patch("#{preferences_service_url}/preferences/#{user_id}") do |req|
            req.body = { settings: preferences_data[:settings] }.to_json
            req.headers.merge!(enhanced_default_headers)
          end
        end
        
        if response.success?
          response.body
        else
          # If update fails, return the preferences data we tried to set
          log_structured_error("Failed to update preferences, using submitted data", {
            user_id: user_id,
            status_code: response.code
          })
          preferences_data.merge(id: "temp_#{user_id}", updated_at: Time.current.iso8601)
        end
      rescue => e
        log_structured_error("Failed to update existing preferences", {
          error: e.message,
          user_id: user_id
        })
        # Return the data we tried to set as fallback
        preferences_data.merge(id: "temp_#{user_id}", updated_at: Time.current.iso8601)
      end
      
      def default_preferences_settings(context)
        # Conservative defaults when service is unavailable
        {
          notifications: {
            email: false,
            push: false,
            sms: false
          },
          privacy: {
            data_sharing: false,
            analytics: false,
            marketing: false
          },
          ui: {
            theme: 'light',
            language: 'en',
            timezone: 'UTC'
          },
          features: {
            newsletter: false,
            product_updates: true,
            security_alerts: true
          }
        }
      end
      
      def preferences_service_url
        ENV.fetch('PREFERENCES_SERVICE_URL', 'http://localhost:3003')
      end
      
      def log_structured_info(message, context = {})
        log_structured(:info, message, { step_name: 'initialize_preferences', service: 'preferences_service' }.merge(context))
      end
      
      def log_structured_error(message, context = {})
        log_structured(:error, message, { step_name: 'initialize_preferences', service: 'preferences_service' }.merge(context))
      end
    end
  end
end