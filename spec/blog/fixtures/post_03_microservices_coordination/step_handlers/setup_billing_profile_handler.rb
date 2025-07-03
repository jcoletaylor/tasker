# frozen_string_literal: true

require_relative '../concerns/api_request_handling'

module BlogExamples
  module Post03
    module StepHandlers
      class SetupBillingProfileHandler < Tasker::StepHandler::Api
        include BlogExamples::Post03::Concerns::ApiRequestHandling

        def process(task, sequence, step)
          set_current_context(task, step, sequence)

          # Extract and validate all required inputs
          billing_inputs = extract_and_validate_inputs(task, sequence, step)

          log_structured_info('Setting up billing profile', {
                                user_id: billing_inputs[:user_id],
                                plan: billing_inputs[:plan]
                              })

          # Create billing profile - this is the core integration
          create_billing_profile(billing_inputs)
        rescue StandardError => e
          Rails.logger.error "Billing profile creation failed: #{e.message}"
          raise
        end

        # Override process_results to set business logic results based on response
        def process_results(step, service_response, _initial_results)
          # Get user_id from the validated inputs
          billing_inputs = extract_and_validate_inputs(@current_task, @current_sequence, step)

          # Set business logic results based on response status
          step.results = case service_response.status
                         when 201
                           process_successful_creation(service_response, billing_inputs[:user_id])
                         when 409
                           process_existing_profile(billing_inputs)
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

        # Extract and validate all required inputs for billing profile creation
        def extract_and_validate_inputs(task, sequence, _step)
          # Normalize all hash keys to symbols for consistent access
          context = task.context.deep_symbolize_keys
          user_info = context[:user_info] || {}
          billing_info = context[:billing_info] || {}

          # Get user ID from previous step
          user_account_step = step_results(sequence, 'create_user_account')
          user_id = user_account_step['user_id']

          unless user_id
            raise Tasker::PermanentError.new(
              'Cannot setup billing profile: user_id not found from create_user_account step',
              error_code: 'MISSING_USER_ID'
            )
          end

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

          # Build validated billing data
          {
            user_id: user_id,
            plan: user_info[:plan] || 'free',
            email: user_info[:email],
            name: user_info[:name],
            company_name: user_info[:company_name],
            payment_method: billing_info[:payment_method],
            billing_address: billing_info[:billing_address] || {}
          }.compact
        end

        # Create billing profile using validated inputs
        def create_billing_profile(billing_inputs)
          start_time = Time.current

          log_api_call(:post, 'billing_service/profiles', timeout: 30)

          # Use mock service
          billing_service = get_service(:billing_service)
          response = billing_service.create_billing_profile(billing_inputs)

          duration_ms = ((Time.current - start_time) * 1000).to_i
          log_api_response(:post, 'billing_service/profiles', response, duration_ms)

          # Return the original response for framework processing
          response
        end

        # Process successful billing profile creation response
        def process_successful_creation(response, user_id)
          billing_response = response.body.deep_symbolize_keys

          ensure_billing_profile_successful!(billing_response)

          log_structured_info('Billing profile created successfully', {
                                user_id: user_id,
                                profile_id: billing_response[:id],
                                plan: billing_response[:plan]
                              })

          {
            profile_id: billing_response[:id],
            user_id: user_id,
            plan: billing_response[:plan],
            correlation_id: correlation_id,
            service_response_time: response.headers['x-response-time'],
            status: 'created'
          }
        end

        # Ensure billing profile creation was successful
        def ensure_billing_profile_successful!(billing_response)
          unless billing_response[:id]
            raise Tasker::PermanentError.new(
              'Billing profile creation appeared successful but no profile ID was returned',
              error_code: 'MISSING_PROFILE_ID_IN_RESPONSE'
            )
          end

          return if billing_response[:plan]

          raise Tasker::PermanentError.new(
            'Billing profile creation appeared successful but no plan was returned',
            error_code: 'MISSING_PLAN_IN_RESPONSE'
          )
        end

        # Process existing billing profile with idempotency
        def process_existing_profile(billing_inputs)
          log_structured_info('Billing profile already exists, treating as idempotent success', {
                                user_id: billing_inputs[:user_id],
                                plan: billing_inputs[:plan]
                              })

          # For idempotent success, return expected format
          {
            profile_id: "existing_profile_#{billing_inputs[:user_id]}",
            user_id: billing_inputs[:user_id],
            plan: billing_inputs[:plan],
            correlation_id: correlation_id,
            status: 'already_exists'
          }
        end

        def log_structured_info(message, context = {})
          log_structured(:info, message,
                         { step_name: 'setup_billing_profile', service: 'billing_service' }.merge(context))
        end

        def log_structured_error(message, context = {})
          log_structured(:error, message,
                         { step_name: 'setup_billing_profile', service: 'billing_service' }.merge(context))
        end
      end
    end
  end
end
