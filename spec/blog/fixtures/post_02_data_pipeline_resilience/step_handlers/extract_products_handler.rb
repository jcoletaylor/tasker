# frozen_string_literal: true

module BlogExamples
  module Post02
    module StepHandlers
      class ExtractProductsHandler < Tasker::StepHandler::Base
        def process(task, sequence, step)
          # Extract and validate all required inputs
          extraction_inputs = extract_and_validate_inputs(task, sequence, step)

          Rails.logger.info "Starting product extraction: task_id=#{task.task_id}"

          # Fire custom event for monitoring
          publish_event('data_extraction_started', {
                          step_name: 'extract_products',
                          task_id: task.id
                        })

          # Extract products data - this is the core integration
          begin
            result = extract_products_data(extraction_inputs)

            # Fire completion event with metrics
            publish_event('data_extraction_completed', {
                            step_name: 'extract_products',
                            records_extracted: result[:metadata][:total_records],
                            task_id: task.id
                          })

            # Return raw extraction results for process_results to handle
            result
          rescue StandardError => e
            Rails.logger.error "Product extraction failed: #{e.message}"

            # Fire failure event
            publish_event('data_extraction_failed', {
                            step_name: 'extract_products',
                            error: e.message,
                            task_id: task.id
                          })

            raise
          end
        end

        # Override process_results to handle business logic and result formatting
        def process_results(step, extraction_response, _initial_results)
          # At this point we know the product extraction succeeded
          # Now safely format the business results

          metadata = extraction_response[:metadata]

          Rails.logger.info "Product extraction completed successfully: #{metadata[:total_records]} records"

          step.results = {
            products_data: extraction_response[:data],
            extraction_metadata: metadata,
            extracted_at: Time.current.iso8601
          }
        rescue StandardError => e
          # If result processing fails, we don't want to retry the extraction
          # Log the error and set a failure result without retrying
          Rails.logger.error "Failed to process product extraction results: #{e.message}"
          step.results = {
            error: true,
            error_message: "Product extraction succeeded but result processing failed: #{e.message}",
            error_code: 'RESULT_PROCESSING_FAILED',
            raw_extraction_response: extraction_response,
            status: 'processing_error'
          }
        end

        private

        # Extract and validate all required inputs for product extraction
        def extract_and_validate_inputs(task, _sequence, _step)
          # For product extraction, we don't need specific inputs beyond task context
          # But we can validate any optional parameters
          {
            task_context: task.context.deep_symbolize_keys
          }
        end

        # Extract products data using validated inputs
        def extract_products_data(_extraction_inputs)
          # Use mock data warehouse service for product extraction
          MockDataWarehouseService.extract_products(
            timeout_seconds: 20 # Default timeout for inventory extraction
          )
        rescue MockDataWarehouseService::TimeoutError => e
          # Temporary failure - can be retried
          raise Tasker::RetryableError, "Inventory extraction timed out: #{e.message}"
        rescue MockDataWarehouseService::ConnectionError => e
          # Temporary failure - connection issues
          raise Tasker::RetryableError, "Inventory connection error: #{e.message}"
        rescue MockDataWarehouseService::AuthenticationError => e
          # Permanent failure - authentication issues
          raise Tasker::PermanentError.new(
            "Inventory authentication failed: #{e.message}",
            error_code: 'INVENTORY_AUTH_FAILED'
          )
        end
      end
    end
  end
end
