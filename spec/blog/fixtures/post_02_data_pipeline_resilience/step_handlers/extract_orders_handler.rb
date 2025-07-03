# frozen_string_literal: true

module BlogExamples
  module Post02
    module StepHandlers
      class ExtractOrdersHandler < Tasker::StepHandler::Base
        def process(task, sequence, step)
          # Extract and validate all required inputs
          extraction_inputs = extract_and_validate_inputs(task, sequence, step)

          Rails.logger.info "Starting order extraction: task_id=#{task.task_id}, date_range=#{extraction_inputs[:start_date]} to #{extraction_inputs[:end_date]}"

          # Fire custom event for monitoring
          publish_event('data_extraction_started', {
                          step_name: 'extract_orders',
                          date_range: extraction_inputs[:date_range],
                          task_id: task.id
                        })

          # Extract orders data - this is the core integration
          begin
            result = extract_orders_data(extraction_inputs)

            # Fire completion event with metrics
            publish_event('data_extraction_completed', {
                            step_name: 'extract_orders',
                            records_extracted: result[:metadata][:total_records],
                            date_range: extraction_inputs[:date_range],
                            task_id: task.id
                          })

            # Return raw extraction results for process_results to handle
            result
          rescue StandardError => e
            Rails.logger.error "Order extraction failed: #{e.message}"

            # Fire failure event
            publish_event('data_extraction_failed', {
                            step_name: 'extract_orders',
                            error: e.message,
                            date_range: extraction_inputs[:date_range],
                            task_id: task.id
                          })

            raise
          end
        end

        # Override process_results to handle business logic and result formatting
        def process_results(step, extraction_response, _initial_results)
          # At this point we know the order extraction succeeded
          # Now safely format the business results

          metadata = extraction_response[:metadata]

          Rails.logger.info "Order extraction completed successfully: #{metadata[:total_records]} records"

          step.results = {
            orders_data: extraction_response[:data],
            extraction_metadata: metadata,
            extracted_at: Time.current.iso8601
          }
        rescue StandardError => e
          # If result processing fails, we don't want to retry the extraction
          # Log the error and set a failure result without retrying
          Rails.logger.error "Failed to process order extraction results: #{e.message}"
          step.results = {
            error: true,
            error_message: "Order extraction succeeded but result processing failed: #{e.message}",
            error_code: 'RESULT_PROCESSING_FAILED',
            raw_extraction_response: extraction_response,
            status: 'processing_error'
          }
        end

        private

        # Extract and validate all required inputs for order extraction
        def extract_and_validate_inputs(task, _sequence, _step)
          # Normalize all hash keys to symbols for consistent access
          date_range = task.context['date_range']&.deep_symbolize_keys

          unless date_range
            raise Tasker::PermanentError.new(
              'Date range is required but was not provided',
              error_code: 'MISSING_DATE_RANGE'
            )
          end

          start_date = date_range[:start_date]
          end_date = date_range[:end_date]

          unless start_date
            raise Tasker::PermanentError.new(
              'Start date is required but was not provided',
              error_code: 'MISSING_START_DATE'
            )
          end

          unless end_date
            raise Tasker::PermanentError.new(
              'End date is required but was not provided',
              error_code: 'MISSING_END_DATE'
            )
          end

          # Validate date range makes sense
          begin
            start_parsed = Date.parse(start_date)
            end_parsed = Date.parse(end_date)

            if start_parsed > end_parsed
              raise Tasker::PermanentError.new(
                'Start date cannot be after end date',
                error_code: 'INVALID_DATE_RANGE'
              )
            end
          rescue Date::Error => e
            raise Tasker::PermanentError.new(
              "Invalid date format: #{e.message}",
              error_code: 'INVALID_DATE_FORMAT'
            )
          end

          {
            date_range: date_range,
            start_date: start_date,
            end_date: end_date,
            force_refresh: task.context['force_refresh'] || false
          }
        end

        # Extract orders data using validated inputs
        def extract_orders_data(extraction_inputs)
          # Use mock data warehouse service for extraction
          MockDataWarehouseService.extract_orders(
            start_date: extraction_inputs[:start_date],
            end_date: extraction_inputs[:end_date],
            timeout_seconds: 30 # Default timeout for testing
          )
        rescue MockDataWarehouseService::TimeoutError => e
          # Temporary failure - can be retried
          raise Tasker::RetryableError, "Data warehouse extraction timed out: #{e.message}"
        rescue MockDataWarehouseService::ConnectionError => e
          # Temporary failure - connection issues
          raise Tasker::RetryableError, "Data warehouse connection error: #{e.message}"
        rescue MockDataWarehouseService::InvalidQueryError => e
          # Permanent failure - bad query parameters
          raise Tasker::PermanentError.new(
            "Invalid extraction query: #{e.message}",
            error_code: 'INVALID_EXTRACTION_QUERY'
          )
        end
      end
    end
  end
end
