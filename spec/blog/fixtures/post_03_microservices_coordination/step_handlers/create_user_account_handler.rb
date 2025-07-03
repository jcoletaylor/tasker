# frozen_string_literal: true

require_relative '../concerns/api_request_handling'

module BlogExamples
  module Post03
    module StepHandlers
      class CreateUserAccountHandler < Tasker::StepHandler::Api
        include BlogExamples::Post03::Concerns::ApiRequestHandling

        def process(task, sequence, step)
          set_current_context(task, step, sequence)

          # Extract and validate all required inputs
          user_inputs = extract_and_validate_inputs(task, sequence, step)

          log_structured(:info, 'Creating user account', {
                           email: user_inputs[:email],
                           plan: user_inputs[:plan]
                         })

          # Create user account - this is the core integration
          create_user_account(user_inputs)
        rescue StandardError => e
          Rails.logger.error "User account creation failed: #{e.message}"
          raise
        end

        # Override process_results to set business logic results based on response
        def process_results(step, service_response, _initial_results)
          # Set business logic results based on response status
          case service_response.status
          when 201
            step.results = process_successful_creation(service_response)
          when 409
            # For 409, we need to check if it's idempotent
            user_inputs = extract_and_validate_inputs(@current_task, @current_sequence, step)
            step.results = process_existing_user(user_inputs, service_response)
          else
            # For other statuses, let the framework handle the error
            # The ResponseProcessor will raise appropriate errors
            step.results = {
              error: true,
              status_code: service_response.status,
              response_body: service_response.body
            }
          end
        end

        private

        # Extract and validate all required inputs for user account creation
        def extract_and_validate_inputs(task, _sequence, _step)
          # Normalize all hash keys to symbols for consistent access
          context = task.context.deep_symbolize_keys
          user_info = context[:user_info] || {}

          unless user_info[:email]
            raise Tasker::PermanentError.new(
              'Email is required but was not provided',
              error_code: 'MISSING_EMAIL'
            )
          end

          unless user_info[:name]
            raise Tasker::PermanentError.new(
              'Name is required but was not provided',
              error_code: 'MISSING_NAME'
            )
          end

          # Build validated user data with defaults
          {
            email: user_info[:email],
            name: user_info[:name],
            phone: user_info[:phone],
            plan: user_info[:plan] || 'free',
            marketing_consent: context[:preferences]&.dig(:marketing_emails) || false,
            referral_code: user_info[:referral_code],
            source: user_info[:source] || 'web'
          }.compact
        end

        # Create user account using validated inputs
        def create_user_account(user_inputs)
          start_time = Time.current

          log_api_call(:post, 'user_service/users', timeout: 30)

          # Use mock service - Tasker's circuit breaker logic handled by retry system
          user_service = get_service(:user_service)
          response = user_service.create_user(user_inputs)

          duration_ms = ((Time.current - start_time) * 1000).to_i
          log_api_response(:post, 'user_service/users', response, duration_ms)

          # Return the original response for framework processing
          response
        end

        # Process successful user creation response
        def process_successful_creation(response)
          user_response = response.body.deep_symbolize_keys

          ensure_user_creation_successful!(user_response)

          log_structured_info('User account created successfully', {
                                user_id: user_response[:id],
                                email: user_response[:email]
                              })

          {
            user_id: user_response[:id],
            email: user_response[:email],
            created_at: user_response[:created_at],
            correlation_id: correlation_id,
            service_response_time: response.headers['x-response-time'],
            status: 'created'
          }
        end

        # Ensure user creation was successful
        def ensure_user_creation_successful!(user_response)
          unless user_response[:id]
            raise Tasker::PermanentError.new(
              'User creation appeared successful but no user ID was returned',
              error_code: 'MISSING_USER_ID_IN_RESPONSE'
            )
          end

          return if user_response[:email]

          raise Tasker::PermanentError.new(
            'User creation appeared successful but no email was returned',
            error_code: 'MISSING_EMAIL_IN_RESPONSE'
          )
        end

        # Process existing user with idempotency check
        def process_existing_user(user_inputs, _response)
          log_structured_info('User already exists, checking for idempotency', {
                                email: user_inputs[:email]
                              })

          existing_user = get_existing_user(user_inputs[:email])

          if existing_user && user_matches?(existing_user, user_inputs)
            log_structured_info('Existing user matches, treating as idempotent success', {
                                  user_id: existing_user[:id]
                                })

            {
              user_id: existing_user[:id],
              email: existing_user[:email],
              created_at: existing_user[:created_at],
              correlation_id: correlation_id,
              status: 'already_exists'
            }
          else
            raise Tasker::PermanentError.new(
              "User with email #{user_inputs[:email]} already exists with different data",
              error_code: 'USER_CONFLICT'
            )
          end
        end

        # Get existing user for idempotency check
        def get_existing_user(email)
          # Tasker's retry system will handle failures automatically
          user_service = get_service(:user_service)
          response = user_service.get_user_by_email(email)

          response.success? ? response.body.deep_symbolize_keys : nil
        rescue Tasker::PermanentError => e
          # Don't retry permanent failures (like 404s)
          log_structured_error('Permanent error checking existing user', {
                                 error: e.message,
                                 email: email
                               })
          nil
        rescue StandardError => e
          # Re-raise other errors for Tasker's retry system to handle
          log_structured_error('Failed to check existing user', {
                                 error: e.message,
                                 email: email
                               })
          raise
        end

        # Check if existing user matches new user data for idempotency
        def user_matches?(existing_user, new_user_data)
          # Check if core attributes match for idempotency
          existing_user &&
            existing_user[:email] == new_user_data[:email] &&
            existing_user[:name] == new_user_data[:name] &&
            existing_user[:plan] == new_user_data[:plan]
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
end
