# frozen_string_literal: true

module BlogExamples
  module Post02
    module StepHandlers
      class GenerateInsightsHandler < Tasker::StepHandler::Base
        def process(task, sequence, step)
          # Extract and validate all required inputs
          insights_inputs = extract_and_validate_inputs(task, sequence, step)

          Rails.logger.info "Starting business insights generation: task_id=#{task.task_id}"

          # Generate insights - this is the core integration
          begin
            generate_business_insights(insights_inputs)

            # Return raw insights generation results for process_results to handle
          rescue StandardError => e
            Rails.logger.error "Business insights generation failed: #{e.message}"
            raise
          end
        end

        # Override process_results to handle business logic and result formatting
        def process_results(step, insights_response, _initial_results)
          # At this point we know the insights generation succeeded
          # Now safely format the business results

          Rails.logger.info 'Business insights generation completed successfully'

          step.results = {
            insights: insights_response[:data],
            insights_metadata: insights_response[:metadata],
            generated_at: Time.current.iso8601
          }
        rescue StandardError => e
          # If result processing fails, we don't want to retry the insights generation
          # Log the error and set a failure result without retrying
          Rails.logger.error "Failed to process insights generation results: #{e.message}"
          step.results = {
            error: true,
            error_message: "Insights generation succeeded but result processing failed: #{e.message}",
            error_code: 'RESULT_PROCESSING_FAILED',
            raw_insights_response: insights_response,
            status: 'processing_error'
          }
        end

        private

        # Extract and validate all required inputs for insights generation
        def extract_and_validate_inputs(task, sequence, _step)
          # Get data from dependent transformation steps with normalized keys
          customer_step = get_dependent_step(sequence, 'transform_customer_metrics')
          product_step = get_dependent_step(sequence, 'transform_product_metrics')

          customer_metrics = customer_step&.results&.deep_symbolize_keys&.dig(:customer_metrics)
          product_metrics = product_step&.results&.deep_symbolize_keys&.dig(:product_metrics)

          unless customer_metrics
            raise Tasker::PermanentError.new(
              'Customer metrics are required but were not found from transform_customer_metrics step',
              error_code: 'MISSING_CUSTOMER_METRICS'
            )
          end

          unless product_metrics
            raise Tasker::PermanentError.new(
              'Product metrics are required but were not found from transform_product_metrics step',
              error_code: 'MISSING_PRODUCT_METRICS'
            )
          end

          {
            customer_metrics: customer_metrics,
            product_metrics: product_metrics,
            task_context: task.context.deep_symbolize_keys
          }
        end

        # Generate business insights using validated inputs
        def generate_business_insights(insights_inputs)
          # Use mock data warehouse service for insight generation
          MockDataWarehouseService.generate_insights(
            customer_metrics: insights_inputs[:customer_metrics],
            product_metrics: insights_inputs[:product_metrics],
            timeout_seconds: 30 # Default timeout for insights generation
          )
        rescue MockDataWarehouseService::TimeoutError => e
          # Temporary failure - can be retried
          raise Tasker::RetryableError, "Insights generation timed out: #{e.message}"
        rescue MockDataWarehouseService::ConnectionError => e
          # Temporary failure - connection issues
          raise Tasker::RetryableError, "Data warehouse connection error: #{e.message}"
        rescue MockDataWarehouseService::InsufficientDataError => e
          # Permanent failure - not enough data to generate insights
          raise Tasker::PermanentError.new(
            "Insufficient data for insights generation: #{e.message}",
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
