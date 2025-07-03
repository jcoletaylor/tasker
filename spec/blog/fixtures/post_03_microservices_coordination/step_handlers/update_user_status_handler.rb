# frozen_string_literal: true

require_relative '../concerns/api_request_handling'

module BlogExamples
  module Post03
    module StepHandlers
      class UpdateUserStatusHandler < Tasker::StepHandler::Api
        include BlogExamples::Post03::Concerns::ApiRequestHandling

        def process(task, sequence, step)
          set_current_context(task, step, sequence)

          # Extract and validate all required inputs
          status_inputs = extract_and_validate_inputs(task, sequence, step)

          log_structured_info('Updating user registration status to complete', {
                                user_id: status_inputs[:user_id],
                                completed_steps: status_inputs[:completed_steps].length
                              })

          # Update user status - this is the core integration
          update_user_registration_status(status_inputs)
        rescue StandardError => e
          Rails.logger.error "User status update failed: #{e.message}"
          raise
        end

        private

        # Extract and validate all required inputs for user status update
        def extract_and_validate_inputs(_task, sequence, _step)
          # Get user ID from previous step
          user_account_step = step_results(sequence, 'create_user_account')
          user_id = user_account_step['user_id']

          unless user_id
            raise Tasker::PermanentError.new(
              'Cannot update user status: user_id not found from create_user_account step',
              error_code: 'MISSING_USER_ID'
            )
          end

          # Gather completion data from all previous steps
          gather_completion_data(sequence, user_id)

          # Return validated inputs
        end

        # Update user registration status using validated inputs
        def update_user_registration_status(status_inputs)
          start_time = Time.current

          log_api_call(:patch, "user_service/users/#{status_inputs[:user_id]}/status", timeout: 10)

          # Use mock service
          user_service = get_service(:user_service)
          response = user_service.update_user_status(status_inputs[:user_id], status_inputs)

          duration_ms = ((Time.current - start_time) * 1000).to_i
          log_api_response(:patch, "user_service/users/#{status_inputs[:user_id]}/status", response, duration_ms)

          case response.status
          when 200
            # Status updated successfully
            process_successful_update(response, status_inputs)
          when 404
            # User not found - permanent error
            raise Tasker::PermanentError.new(
              "User not found for status update: #{status_inputs[:user_id]}",
              error_code: 'USER_NOT_FOUND'
            )
          else
            # Let framework handle other responses
            handle_microservice_response(response, 'user_service')
          end
        end

        # Gather completion data from all previous steps
        def gather_completion_data(sequence, user_id)
          completed_steps = []
          step_details = {}

          # Collect results from all previous steps
          %w[create_user_account setup_billing_profile initialize_preferences send_welcome_sequence].each do |step_name|
            step_result = step_results(sequence, step_name)
            next if step_result.blank?

            completed_steps << step_name
            step_details[step_name] = {
              completed_at: Time.current.iso8601,
              status: step_result['status'] || 'completed'
            }
          end

          {
            user_id: user_id,
            status: 'registration_complete',
            completed_steps: completed_steps,
            step_details: step_details,
            completion_timestamp: Time.current.iso8601
          }
        end

        # Process successful user status update
        def process_successful_update(response, status_inputs)
          user_response = response.body.deep_symbolize_keys

          ensure_status_update_successful!(user_response)

          log_structured_info('User registration status updated successfully', {
                                user_id: status_inputs[:user_id],
                                new_status: user_response[:status],
                                completed_steps: status_inputs[:completed_steps].length
                              })

          {
            user_id: status_inputs[:user_id],
            status: user_response[:status],
            completed_steps: status_inputs[:completed_steps],
            registration_complete: true,
            correlation_id: correlation_id,
            service_response_time: response.headers['x-response-time'],
            completion_timestamp: status_inputs[:completion_timestamp]
          }
        end

        # Ensure status update was successful
        def ensure_status_update_successful!(user_response)
          return if user_response[:status]

          raise Tasker::PermanentError.new(
            'User status update appeared successful but no status was returned',
            error_code: 'MISSING_STATUS_IN_RESPONSE'
          )
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
end
