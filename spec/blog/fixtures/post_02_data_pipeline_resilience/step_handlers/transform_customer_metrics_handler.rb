# frozen_string_literal: true

module BlogExamples
  module Post02
    module StepHandlers
      class TransformCustomerMetricsHandler < Tasker::StepHandler::Base
        def process(task, sequence, step)
          # Extract and validate all required inputs
          transformation_inputs = extract_and_validate_inputs(task, sequence, step)

          Rails.logger.info "Starting customer metrics transformation: task_id=#{task.task_id}"

          # Transform customer metrics - this is the core integration
          begin
            transform_customer_metrics(transformation_inputs)

            # Return raw transformation results for process_results to handle
          rescue StandardError => e
            Rails.logger.error "Customer metrics transformation failed: #{e.message}"
            raise
          end
        end

        # Override process_results to handle business logic and result formatting
        def process_results(step, transformation_response, _initial_results)
          # At this point we know the customer metrics transformation succeeded
          # Now safely format the business results

          metadata = transformation_response[:metadata]

          Rails.logger.info "Customer metrics transformation completed successfully: #{metadata[:total_customers]} customers"

          step.results = {
            customer_metrics: transformation_response[:data],
            transformation_metadata: metadata,
            transformed_at: Time.current.iso8601
          }
        rescue StandardError => e
          # If result processing fails, we don't want to retry the transformation
          # Log the error and set a failure result without retrying
          Rails.logger.error "Failed to process customer metrics transformation results: #{e.message}"
          step.results = {
            error: true,
            error_message: "Customer metrics transformation succeeded but result processing failed: #{e.message}",
            error_code: 'RESULT_PROCESSING_FAILED',
            raw_transformation_response: transformation_response,
            status: 'processing_error'
          }
        end

        private

        # Extract and validate all required inputs for customer metrics transformation
        def extract_and_validate_inputs(task, sequence, _step)
          # Get data from dependent steps with normalized keys
          orders_step = get_dependent_step(sequence, 'extract_orders')
          users_step = get_dependent_step(sequence, 'extract_users')

          orders_data = orders_step&.results&.deep_symbolize_keys&.dig(:orders_data)
          users_data = users_step&.results&.deep_symbolize_keys&.dig(:users_data)

          unless orders_data
            raise Tasker::PermanentError.new(
              'Orders data is required but was not found from extract_orders step',
              error_code: 'MISSING_ORDERS_DATA'
            )
          end

          unless users_data
            raise Tasker::PermanentError.new(
              'Users data is required but was not found from extract_users step',
              error_code: 'MISSING_USERS_DATA'
            )
          end

          {
            orders_data: orders_data,
            users_data: users_data,
            task_context: task.context.deep_symbolize_keys
          }
        end

        # Transform customer metrics using validated inputs
        def transform_customer_metrics(transformation_inputs)
          # Use mock data warehouse service for transformation
          MockDataWarehouseService.transform_customer_metrics(
            orders_data: transformation_inputs[:orders_data],
            users_data: transformation_inputs[:users_data],
            timeout_seconds: 60 # Default timeout for customer metrics transformation
          )
        rescue MockDataWarehouseService::TimeoutError => e
          # Temporary failure - can be retried
          raise Tasker::RetryableError, "Customer metrics transformation timed out: #{e.message}"
        rescue MockDataWarehouseService::ConnectionError => e
          # Temporary failure - connection issues
          raise Tasker::RetryableError, "Data warehouse connection error: #{e.message}"
        rescue MockDataWarehouseService::InsufficientDataError => e
          # Permanent failure - not enough data to transform
          raise Tasker::PermanentError.new(
            "Insufficient data for customer metrics transformation: #{e.message}",
            error_code: 'INSUFFICIENT_DATA'
          )
        end

        def get_dependent_step(sequence, step_name)
          sequence.steps.find { |s| s.name == step_name }
        end
      end
    end
  end
end
