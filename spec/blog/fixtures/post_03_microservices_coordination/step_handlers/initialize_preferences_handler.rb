# frozen_string_literal: true

require_relative '../concerns/api_request_handling'

module BlogExamples
  module Post03
    module StepHandlers
      class InitializePreferencesHandler < Tasker::StepHandler::Api
        include BlogExamples::Post03::Concerns::ApiRequestHandling

        def process(task, sequence, step)
          set_current_context(task, step, sequence)

          # Extract and validate all required inputs
          preferences_inputs = extract_and_validate_inputs(task, sequence, step)

          log_structured_info('Initializing user preferences', {
                                user_id: preferences_inputs[:user_id],
                                marketing_consent: preferences_inputs[:marketing_consent]
                              })

          # Initialize preferences - this is the core integration
          initialize_user_preferences(preferences_inputs)
        rescue StandardError => e
          Rails.logger.error "User preferences initialization failed: #{e.message}"
          raise
        end

        # Override process_results to set business logic results based on response
        def process_results(step, service_response, _initial_results)
          # Get user_id from the validated inputs
          preferences_inputs = extract_and_validate_inputs(@current_task, @current_sequence, step)

          # Set business logic results based on response status
          step.results = case service_response.status
                         when 201
                           process_successful_creation(service_response, preferences_inputs[:user_id])
                         when 409
                           process_existing_preferences(preferences_inputs)
                         else
                           # For other statuses, let the framework handle the error
                           {
                             error: true,
                             status_code: service_response.status,
                             response_body: service_response.body
                           }
                         end
        end

        private

        # Extract and validate all required inputs for preferences initialization
        def extract_and_validate_inputs(task, sequence, _step)
          # Normalize all hash keys to symbols for consistent access
          context = task.context.deep_symbolize_keys
          user_info = context[:user_info] || {}
          preferences = context[:preferences] || {}

          # Get user ID from previous step
          user_account_step = step_results(sequence, 'create_user_account')
          user_id = user_account_step['user_id']

          unless user_id
            raise Tasker::PermanentError.new(
              'Cannot initialize preferences: user_id not found from create_user_account step',
              error_code: 'MISSING_USER_ID'
            )
          end

          # Build validated preferences data with defaults
          {
            user_id: user_id,
            marketing_consent: preferences[:marketing_emails] || false,
            newsletter_frequency: preferences[:newsletter] ? 'weekly' : 'never',
            notification_settings: {
              email_notifications: preferences[:product_updates] || true,
              sms_notifications: false,
              push_notifications: true
            },
            theme: 'light',
            language: 'en',
            timezone: user_info[:timezone] || 'UTC'
          }.compact
        end

        # Initialize user preferences using validated inputs
        def initialize_user_preferences(preferences_inputs)
          start_time = Time.current

          log_api_call(:post, 'preferences_service/preferences', timeout: 20)

          # Use mock service
          preferences_service = get_service(:preferences_service)
          response = preferences_service.initialize_preferences(preferences_inputs[:user_id], preferences_inputs)

          duration_ms = ((Time.current - start_time) * 1000).to_i
          log_api_response(:post, 'preferences_service/preferences', response, duration_ms)

          # Return the original response for framework processing
          response
        end

        # Process successful preferences initialization response
        def process_successful_creation(response, user_id)
          preferences_response = response.body.deep_symbolize_keys

          ensure_preferences_initialization_successful!(preferences_response)

          log_structured_info('User preferences initialized successfully', {
                                user_id: user_id,
                                preferences_id: preferences_response[:id]
                              })

          {
            preferences_id: preferences_response[:id],
            user_id: user_id,
            correlation_id: correlation_id,
            service_response_time: response.headers['x-response-time'],
            status: 'created'
          }
        end

        # Validate successful preferences creation
        def ensure_preferences_initialization_successful!(response_data)
          # Check if preferences ID was returned
          unless response_data[:id]
            raise Tasker::PermanentError.new(
              'Preferences initialization appeared successful but no preferences ID was returned',
              error_code: 'MISSING_PREFERENCES_ID'
            )
          end

          # Validate that preferences data structure is present
          unless response_data[:preferences]
            raise Tasker::PermanentError.new(
              'Preferences initialization appeared successful but no preferences data was returned',
              error_code: 'MISSING_PREFERENCES_DATA'
            )
          end

          true
        end

        # Process existing preferences with idempotency
        def process_existing_preferences(preferences_inputs)
          log_structured_info('User preferences already exist, treating as idempotent success', {
                                user_id: preferences_inputs[:user_id]
                              })

          # For idempotent success, return expected format
          {
            preferences_id: "existing_prefs_#{preferences_inputs[:user_id]}",
            user_id: preferences_inputs[:user_id],
            correlation_id: correlation_id,
            status: 'already_exists'
          }
        end

        def log_structured_info(message, context = {})
          log_structured(:info, message,
                         { step_name: 'initialize_preferences', service: 'preferences_service' }.merge(context))
        end

        def log_structured_error(message, context = {})
          log_structured(:error, message,
                         { step_name: 'initialize_preferences', service: 'preferences_service' }.merge(context))
        end
      end
    end
  end
end
