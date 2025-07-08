# frozen_string_literal: true

module BlogExamples
  module Post04
    module StepHandlers
      class ExecuteRefundWorkflowHandler < Tasker::StepHandler::Api
        def process(task, sequence, step)
          # Extract and validate inputs using our gold standard pattern
          inputs = extract_and_validate_inputs(task, sequence, step)

          Rails.logger.info "Executing cross-namespace refund workflow: #{inputs[:workflow_name]} in #{inputs[:namespace]}"

          # This is the key Post 04 pattern: Cross-namespace workflow coordination
          # Customer Success team calls Payments team's Tasker system via HTTP API
          create_payments_task(inputs)
        end

        def process_results(step, service_response, _initial_results)
          # Safe result processing - format the task creation results
          # Note: We get task creation confirmation, not execution results
          begin
            # Handle both response objects (with .body) and direct hashes
            parsed_response = if service_response.respond_to?(:body)
                               JSON.parse(service_response.body).deep_symbolize_keys
                             else
                               service_response.deep_symbolize_keys
                             end
            
            step.results = {
              task_delegated: true,
              target_namespace: 'payments',
              target_workflow: 'process_refund',
              delegated_task_id: parsed_response[:task_id],
              delegated_task_status: parsed_response[:status],
              delegation_timestamp: Time.current.iso8601,
              correlation_id: parsed_response[:correlation_id]
            }
          rescue JSON::ParserError => e
            raise Tasker::PermanentError,
                  "Failed to parse task creation response: #{e.message}"
          rescue StandardError => e
            # If result processing fails, don't retry the API call
            raise Tasker::PermanentError,
                  "Failed to process task creation results: #{e.message}"
          end
        end

        private

        def extract_and_validate_inputs(task, sequence, _step)
          # Normalize all hash keys to symbols immediately
          normalized_context = task.context.deep_symbolize_keys

          # Get approval results from previous step
          approval_step = sequence.find_step_by_name('get_manager_approval')
          approval_results = approval_step&.results&.deep_symbolize_keys

          unless approval_results&.dig(:approval_obtained)
            raise Tasker::PermanentError,
                  'Manager approval must be obtained before executing refund'
          end

          # Get validation results to extract payment_id
          validation_step = sequence.find_step_by_name('validate_refund_request')
          validation_results = validation_step&.results&.deep_symbolize_keys

          payment_id = validation_results&.dig(:payment_id)
          unless payment_id
            raise Tasker::PermanentError,
                  'Payment ID not found in validation results'
          end

          # Map customer success context to payments workflow input
          # This demonstrates how different teams have different data models
          {
            namespace: 'payments',
            workflow_name: 'process_refund',
            workflow_version: '2.1.0',
            context: {
              # Map customer service ticket to payment ID
              payment_id: payment_id,
              refund_amount: normalized_context[:refund_amount],
              refund_reason: normalized_context[:refund_reason],
              # Include cross-team coordination metadata
              initiated_by: 'customer_success',
              approval_id: approval_results[:approval_id],
              ticket_id: normalized_context[:ticket_id],
              correlation_id: normalized_context[:correlation_id] || generate_correlation_id
            }
          }
        end

        def generate_correlation_id
          # Generate a correlation ID for cross-team tracking
          "cs-#{SecureRandom.hex(8)}"
        end

        def create_payments_task(inputs)
          # Make HTTP call to payments team's Tasker system
          # This demonstrates the cross-namespace coordination pattern
          response = connection.post('/tasker/tasks', inputs)

          # Check response status and handle errors appropriately
          case response.status
          when 201, 200
            # Check response body for actual task creation status
            parsed_response = JSON.parse(response.body).deep_symbolize_keys
            case parsed_response[:status]
            when 'failed'
              raise Tasker::PermanentError,
                    "Task creation failed: #{parsed_response[:error_message]}"
            when 'rejected'
              raise Tasker::PermanentError,
                    "Task creation rejected: #{parsed_response[:rejection_reason]}"
            when 'created', 'queued'
              # Task was successfully created
              unless parsed_response[:task_id]
                raise Tasker::PermanentError,
                      'Task created but no task_id returned'
              end
              response
            else
              raise Tasker::RetryableError,
                    "Unexpected task creation status: #{parsed_response[:status]}"
            end
          when 400
            raise Tasker::PermanentError,
                  'Invalid task creation request'
          when 403
            raise Tasker::PermanentError,
                  'Not authorized to create tasks in payments namespace'
          when 404
            raise Tasker::PermanentError,
                  'Payments workflow definition not found'
          when 429
            raise Tasker::RetryableError,
                  'Task creation rate limited'
          when 500, 502, 503, 504
            raise Tasker::RetryableError,
                  'Tasker system unavailable'
          else
            raise Tasker::RetryableError,
                  "Unexpected response status: #{response.status}"
          end
        end

        # Note: Configuration in YAML step template or test setup:
        # step_templates:
        #   - name: execute_refund_workflow
        #     handler_class: "ExecuteRefundWorkflowHandler"
        #     default_retry_limit: 3              # Step template level
        #     default_retryable: true             # Step template level
        #     handler_config:                     # API config level
        #       url: "http://payments-service.example.com"
        #       retry_delay: 2.0
        #       enable_exponential_backoff: true
      end
    end
  end
end
