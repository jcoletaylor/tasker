# frozen_string_literal: true

module BlogExamples
  module Post02
    module StepHandlers
      class TransformProductMetricsHandler < Tasker::StepHandler::Base
        def process(task, sequence, step)
          # Extract and validate all required inputs
          transformation_inputs = extract_and_validate_inputs(task, sequence, step)

          Rails.logger.info "Starting product metrics transformation: task_id=#{task.task_id}"

          # Transform product metrics - this is the core integration
          begin
            transform_product_metrics(transformation_inputs)

            # Return raw transformation results for process_results to handle
          rescue StandardError => e
            Rails.logger.error "Product metrics transformation failed: #{e.message}"
            raise
          end
        end

        # Override process_results to handle business logic and result formatting
        def process_results(step, transformation_response, _initial_results)
          # At this point we know the product metrics transformation succeeded
          # Now safely format the business results

          metadata = transformation_response[:metadata]

          Rails.logger.info "Product metrics transformation completed successfully: #{metadata[:total_products]} products"

          step.results = {
            product_metrics: transformation_response[:data],
            transformation_metadata: metadata,
            transformed_at: Time.current.iso8601
          }
        rescue StandardError => e
          # If result processing fails, we don't want to retry the transformation
          # Log the error and set a failure result without retrying
          Rails.logger.error "Failed to process product metrics transformation results: #{e.message}"
          step.results = {
            error: true,
            error_message: "Product metrics transformation succeeded but result processing failed: #{e.message}",
            error_code: 'RESULT_PROCESSING_FAILED',
            raw_transformation_response: transformation_response,
            status: 'processing_error'
          }
        end

        private

        # Extract and validate all required inputs for product metrics transformation
        def extract_and_validate_inputs(task, sequence, _step)
          # Get data from dependent steps with normalized keys
          orders_step = get_dependent_step(sequence, 'extract_orders')
          products_step = get_dependent_step(sequence, 'extract_products')

          orders_data = orders_step&.results&.deep_symbolize_keys&.dig(:orders_data)
          products_data = products_step&.results&.deep_symbolize_keys&.dig(:products_data)

          unless orders_data
            raise Tasker::PermanentError.new(
              'Orders data is required but was not found from extract_orders step',
              error_code: 'MISSING_ORDERS_DATA'
            )
          end

          unless products_data
            raise Tasker::PermanentError.new(
              'Products data is required but was not found from extract_products step',
              error_code: 'MISSING_PRODUCTS_DATA'
            )
          end

          {
            orders_data: orders_data,
            products_data: products_data,
            task_context: task.context.deep_symbolize_keys
          }
        end

        # Transform product metrics using validated inputs
        def transform_product_metrics(transformation_inputs)
          # Use mock data warehouse service for transformation
          MockDataWarehouseService.transform_product_metrics(
            orders_data: transformation_inputs[:orders_data],
            products_data: transformation_inputs[:products_data],
            timeout_seconds: 45 # Default timeout for product metrics transformation
          )
        rescue MockDataWarehouseService::TimeoutError => e
          # Temporary failure - can be retried
          raise Tasker::RetryableError, "Product metrics transformation timed out: #{e.message}"
        rescue MockDataWarehouseService::ConnectionError => e
          # Temporary failure - connection issues
          raise Tasker::RetryableError, "Data warehouse connection error: #{e.message}"
        rescue MockDataWarehouseService::InsufficientDataError => e
          # Permanent failure - not enough data to transform
          raise Tasker::PermanentError.new(
            "Insufficient data for product metrics transformation: #{e.message}",
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
