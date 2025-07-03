# frozen_string_literal: true

require_relative '../concerns/api_request_handling'

module BlogExamples
  module Post03
    module StepHandlers
      class SendWelcomeSequenceHandler < Tasker::StepHandler::Api
        include BlogExamples::Post03::Concerns::ApiRequestHandling

        def process(task, sequence, step)
          set_current_context(task, step, sequence)

          # Extract and validate all required inputs
          notification_inputs = extract_and_validate_inputs(task, sequence, step)

          log_structured_info('Sending welcome sequence', {
                                user_id: notification_inputs[:user_id],
                                plan: notification_inputs[:plan],
                                email: notification_inputs[:email]
                              })

          # Send welcome sequence - this is the core integration
          send_welcome_notifications(notification_inputs)
        rescue StandardError => e
          Rails.logger.error "Welcome sequence sending failed: #{e.message}"
          raise
        end

        # Override process_results to set business logic results based on response
        def process_results(step, service_response, _initial_results)
          # Get data from validated inputs for business logic
          notification_inputs = extract_and_validate_inputs(@current_task, @current_sequence, step)

          # Set business logic results based on response status
          case service_response.status
          when 200, 201
            step.results = process_successful_send(service_response, notification_inputs)
          when 429
            # Rate limited - will be retried by framework
            raise Tasker::RetryableError.new(
              'Notification service rate limited',
              retry_after: service_response.headers['retry-after']&.to_i || 30
            )
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

        # Extract and validate all required inputs for welcome sequence sending
        def extract_and_validate_inputs(task, sequence, _step)
          # Normalize all hash keys to symbols for consistent access
          context = task.context.deep_symbolize_keys
          user_info = context[:user_info] || {}

          # Get data from previous steps
          user_account_step = step_results(sequence, 'create_user_account')
          billing_step = step_results(sequence, 'setup_billing_profile')
          step_results(sequence, 'initialize_preferences')

          user_id = user_account_step['user_id']
          plan = billing_step['plan'] || user_info[:plan] || 'free'

          unless user_id
            raise Tasker::PermanentError.new(
              'Cannot send welcome sequence: user_id not found from create_user_account step',
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

          # Build validated notification data
          {
            user_id: user_id,
            email: user_info[:email],
            name: user_info[:name],
            plan: plan,
            sequence_type: 'welcome',
            personalization: {
              plan_features: get_plan_features(plan),
              onboarding_steps: get_onboarding_steps(plan)
            }
          }.compact
        end

        # Send welcome notifications using validated inputs
        def send_welcome_notifications(notification_inputs)
          start_time = Time.current

          log_api_call(:post, 'notification_service/notifications/welcome', timeout: 15)

          # Use mock service
          notification_service = get_service(:notification_service)
          response = notification_service.send_welcome_sequence(notification_inputs[:user_id], notification_inputs)

          duration_ms = ((Time.current - start_time) * 1000).to_i
          log_api_response(:post, 'notification_service/notifications/welcome', response, duration_ms)

          # Return the original response for framework processing
          response
        end

        # Get plan-specific features for personalization
        def get_plan_features(plan)
          case plan
          when 'enterprise'
            %w[advanced_analytics priority_support custom_integrations dedicated_account_manager]
          when 'pro'
            %w[analytics priority_support integrations]
          else # free
            %w[basic_features community_support]
          end
        end

        # Get plan-specific onboarding steps for personalization
        def get_onboarding_steps(plan)
          base_steps = %w[complete_profile verify_email tour_dashboard]

          case plan
          when 'enterprise'
            base_steps + %w[schedule_onboarding_call setup_sso configure_integrations]
          when 'pro'
            base_steps + %w[setup_integrations configure_analytics]
          else # free
            base_steps + ['upgrade_prompt']
          end
        end

        # Process successful welcome sequence sending response
        def process_successful_send(response, notification_inputs)
          notification_response = response.body.deep_symbolize_keys

          ensure_welcome_sequence_successful!(notification_response)

          log_structured_info('Welcome sequence sent successfully', {
                                user_id: notification_inputs[:user_id],
                                sequence_id: notification_response[:sequence_id],
                                emails_sent: notification_response[:email_ids]&.length || 0
                              })

          {
            sequence_id: notification_response[:sequence_id],
            user_id: notification_inputs[:user_id],
            plan: notification_inputs[:plan],
            emails_sent: notification_response[:email_ids]&.length || 0,
            email_ids: notification_response[:email_ids] || [],
            correlation_id: correlation_id,
            service_response_time: response.headers['x-response-time']
          }
        end

        # Ensure welcome sequence sending was successful
        def ensure_welcome_sequence_successful!(notification_response)
          return if notification_response[:sequence_id]

          raise Tasker::PermanentError.new(
            'Welcome sequence sending appeared successful but no sequence ID was returned',
            error_code: 'MISSING_SEQUENCE_ID_IN_RESPONSE'
          )
        end

        def log_structured_info(message, context = {})
          log_structured(:info, message,
                         { step_name: 'send_welcome_sequence', service: 'notification_service' }.merge(context))
        end

        def log_structured_error(message, context = {})
          log_structured(:error, message,
                         { step_name: 'send_welcome_sequence', service: 'notification_service' }.merge(context))
        end
      end
    end
  end
end
