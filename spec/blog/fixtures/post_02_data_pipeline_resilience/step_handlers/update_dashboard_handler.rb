# frozen_string_literal: true

module BlogExamples
  module Post02
    module StepHandlers
      class UpdateDashboardHandler < Tasker::StepHandler::Base
        def process(task, sequence, step)
          # Extract and validate all required inputs
          dashboard_inputs = extract_and_validate_inputs(task, sequence, step)

          Rails.logger.info "Starting dashboard update: task_id=#{task.task_id}"

          # Update dashboard - this is the core integration
          begin
            update_dashboard_data(dashboard_inputs)

            # Return raw dashboard update results for process_results to handle
          rescue StandardError => e
            Rails.logger.error "Dashboard update failed: #{e.message}"
            raise
          end
        end

        # Override process_results to handle business logic and result formatting
        def process_results(step, dashboard_response, _initial_results)
          # At this point we know the dashboard update succeeded
          # Now safely format the business results

          Rails.logger.info 'Dashboard update completed successfully'

          step.results = {
            dashboard_update: dashboard_response[:data],
            dashboard_metadata: dashboard_response[:metadata],
            updated_at: Time.current.iso8601
          }
        rescue StandardError => e
          # If result processing fails, we don't want to retry the dashboard update
          # Log the error and set a failure result without retrying
          Rails.logger.error "Failed to process dashboard update results: #{e.message}"
          step.results = {
            error: true,
            error_message: "Dashboard update succeeded but result processing failed: #{e.message}",
            error_code: 'RESULT_PROCESSING_FAILED',
            raw_dashboard_response: dashboard_response,
            status: 'processing_error'
          }
        end

        private

        # Extract and validate all required inputs for dashboard update
        def extract_and_validate_inputs(task, sequence, _step)
          # Get insights from the generate insights step with normalized keys
          insights_step = get_dependent_step(sequence, 'generate_insights')
          insights = insights_step&.results&.deep_symbolize_keys&.dig(:insights)

          unless insights
            raise Tasker::PermanentError.new(
              'Insights data is required but was not found from generate_insights step',
              error_code: 'MISSING_INSIGHTS_DATA'
            )
          end

          {
            insights: insights,
            task_context: task.context.deep_symbolize_keys
          }
        end

        # Update dashboard using validated inputs
        def update_dashboard_data(dashboard_inputs)
          # Use mock dashboard service for update
          MockDashboardService.update_dashboard(
            insights: dashboard_inputs[:insights],
            timeout_seconds: 15 # Default timeout for dashboard update
          )
        rescue MockDashboardService::TimeoutError => e
          # Temporary failure - can be retried
          raise Tasker::RetryableError, "Dashboard update timed out: #{e.message}"
        rescue MockDashboardService::ConnectionError => e
          # Temporary failure - connection issues
          raise Tasker::RetryableError, "Dashboard service connection error: #{e.message}"
        rescue MockDashboardService::AuthenticationError => e
          # Permanent failure - authentication issues
          raise Tasker::PermanentError.new(
            "Dashboard service authentication failed: #{e.message}",
            error_code: 'DASHBOARD_AUTH_FAILED'
          )
        end

        def get_dependent_step(sequence, step_name)
          sequence.steps.find { |s| s.name == step_name }
        end
      end
    end
  end
end

# Mock dashboard data store for demo purposes
class DashboardDataStore
  def self.update(dashboard_name, data)
    Rails.logger.info("Dashboard Updated: #{dashboard_name}")
    Rails.logger.info("Data: #{data.to_json}")

    # In a real implementation, this would update the actual dashboard data store
    # Could be Redis, database, or dashboard service API
    true
  end
end
