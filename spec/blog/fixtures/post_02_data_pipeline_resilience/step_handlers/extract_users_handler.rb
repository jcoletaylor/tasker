# frozen_string_literal: true

module BlogExamples
  module Post02
    module StepHandlers
      class ExtractUsersHandler < Tasker::StepHandler::Base
        def process(task, sequence, step)
          # Extract and validate all required inputs
          extraction_inputs = extract_and_validate_inputs(task, sequence, step)

          Rails.logger.info "Starting user extraction: task_id=#{task.task_id}"

          # Fire custom event for monitoring
          publish_event('data_extraction_started', {
                          step_name: 'extract_users',
                          task_id: task.id
                        })

          # Extract users data - this is the core integration
          begin
            result = extract_users_data(extraction_inputs)

            # Fire completion event with metrics
            publish_event('data_extraction_completed', {
                            step_name: 'extract_users',
                            records_extracted: result[:metadata][:total_records],
                            task_id: task.id
                          })

            # Return raw extraction results for process_results to handle
            result
          rescue StandardError => e
            Rails.logger.error "User extraction failed: #{e.message}"

            # Fire failure event
            publish_event('data_extraction_failed', {
                            step_name: 'extract_users',
                            error: e.message,
                            task_id: task.id
                          })

            raise
          end
        end

        # Override process_results to handle business logic and result formatting
        def process_results(step, extraction_response, _initial_results)
          # At this point we know the user extraction succeeded
          # Now safely format the business results

          metadata = extraction_response[:metadata]

          Rails.logger.info "User extraction completed successfully: #{metadata[:total_records]} records"

          step.results = {
            users_data: extraction_response[:data],
            extraction_metadata: metadata,
            extracted_at: Time.current.iso8601
          }
        rescue StandardError => e
          # If result processing fails, we don't want to retry the extraction
          # Log the error and set a failure result without retrying
          Rails.logger.error "Failed to process user extraction results: #{e.message}"
          step.results = {
            error: true,
            error_message: "User extraction succeeded but result processing failed: #{e.message}",
            error_code: 'RESULT_PROCESSING_FAILED',
            raw_extraction_response: extraction_response,
            status: 'processing_error'
          }
        end

        private

        # Extract and validate all required inputs for user extraction
        def extract_and_validate_inputs(task, _sequence, _step)
          # For user extraction, we don't need specific inputs beyond task context
          # But we can validate any optional parameters
          {
            task_context: task.context.deep_symbolize_keys
          }
        end

        # Extract users data using validated inputs
        def extract_users_data(_extraction_inputs)
          # Use mock data warehouse service for user extraction
          MockDataWarehouseService.extract_users(
            timeout_seconds: 45 # Default timeout for CRM extraction
          )
        rescue MockDataWarehouseService::TimeoutError => e
          # Temporary failure - can be retried
          raise Tasker::RetryableError, "CRM extraction timed out: #{e.message}"
        rescue MockDataWarehouseService::ConnectionError => e
          # Temporary failure - connection issues
          raise Tasker::RetryableError, "CRM connection error: #{e.message}"
        rescue MockDataWarehouseService::AuthenticationError => e
          # Permanent failure - authentication issues
          raise Tasker::PermanentError.new(
            "CRM authentication failed: #{e.message}",
            error_code: 'CRM_AUTH_FAILED'
          )
        end
      end
    end
  end
end
