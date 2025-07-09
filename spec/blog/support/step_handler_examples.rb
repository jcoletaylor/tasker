# frozen_string_literal: true

# Step Handler Pattern Examples
#
# This file contains executable examples demonstrating the patterns
# outlined in STEP_HANDLER_BEST_PRACTICES.md
#
# Each example follows the four-phase pattern:
# 1. Extract and validate inputs
# 2. Execute business logic
# 3. Validate business logic results
# 4. Process results (optional)

module StepHandlerExamples
  # Example 1: Basic Step Handler with Computational Logic
  # Demonstrates: Input validation, business logic, result formatting
  class BasicComputationHandler < Tasker::StepHandler::Base
    def process(task, sequence, step)
      # Phase 1: Extract and validate inputs
      inputs = extract_and_validate_inputs(task, sequence, step)

      Rails.logger.info "Computing shipping for order: #{inputs[:order_id]}"

      # Phase 2: Execute business logic (computation)
      begin
        result = calculate_shipping_cost(inputs)

        # Phase 3: Validate business logic results
        ensure_calculation_valid!(result)

        result
      rescue ArgumentError => e
        # Business logic errors are permanent
        raise Tasker::PermanentError.new(
          "Invalid shipping calculation: #{e.message}",
          error_code: 'INVALID_SHIPPING_DATA'
        )
      end
    end

    def process_results(step, calculation_result, _initial_results)
      # Phase 4: Format and store results safely
      step.results = {
        shipping_cost: calculation_result[:cost],
        shipping_method: calculation_result[:method],
        estimated_delivery: calculation_result[:delivery_date],
        calculation_timestamp: Time.current.iso8601
      }
    rescue StandardError => e
      raise Tasker::PermanentError,
            "Failed to process shipping calculation results: #{e.message}"
    end

    private

    def extract_and_validate_inputs(task, sequence, _step)
      context = task.context.deep_symbolize_keys

      # Validate required fields
      order_id = context[:order_id]
      unless order_id
        raise Tasker::PermanentError.new(
          'Order ID is required for shipping calculation',
          error_code: 'MISSING_ORDER_ID'
        )
      end

      # Get cart details from previous step
      cart_step = sequence.find_step_by_name('validate_cart')
      cart_results = cart_step&.results&.deep_symbolize_keys

      unless cart_results&.dig(:cart_validated)
        raise Tasker::PermanentError,
              'Cart validation must complete before shipping calculation'
      end

      {
        order_id: order_id,
        items: cart_results[:items],
        total_weight: cart_results[:total_weight],
        destination: context[:shipping_address],
        priority: context[:shipping_priority] || 'standard'
      }
    end

    def calculate_shipping_cost(inputs)
      # Business logic: Calculate shipping based on weight and destination
      base_cost = inputs[:total_weight] * 0.50
      distance_multiplier = calculate_distance_multiplier(inputs[:destination])
      priority_multiplier = inputs[:priority] == 'express' ? 2.0 : 1.0

      total_cost = (base_cost * distance_multiplier * priority_multiplier).round(2)
      delivery_days = inputs[:priority] == 'express' ? 1 : 3

      {
        cost: total_cost,
        method: inputs[:priority],
        delivery_date: delivery_days.days.from_now.to_date,
        calculation_details: {
          base_cost: base_cost,
          distance_multiplier: distance_multiplier,
          priority_multiplier: priority_multiplier
        }
      }
    end

    def ensure_calculation_valid!(result)
      unless result[:cost] && result[:cost] > 0
        raise Tasker::PermanentError,
              'Shipping calculation resulted in invalid cost'
      end

      return if result[:delivery_date]

      raise Tasker::PermanentError,
            'Shipping calculation failed to determine delivery date'
    end

    def calculate_distance_multiplier(destination)
      # Simplified distance calculation
      case destination[:country]
      when 'US'
        1.0
      when 'CA', 'MX'
        1.5
      else
        2.0
      end
    end
  end

  # Example 2: API Integration Handler
  # Demonstrates: HTTP API calls, error classification, idempotency
  class UserRegistrationHandler < Tasker::StepHandler::Api
    def process(task, sequence, step)
      # Phase 1: Extract and validate inputs
      inputs = extract_and_validate_inputs(task, sequence, step)

      Rails.logger.info "Registering user: #{inputs[:email]}"

      # Phase 2: Execute business logic (API call)
      response = register_user_via_api(inputs)

      # Phase 3: Validate API response
      handle_api_response(response, inputs)
    end

    def process_results(step, api_response, _initial_results)
      # Phase 4: Process different response scenarios
      step.results = case api_response.status
                     when 201
                       process_successful_registration(api_response)
                     when 409
                       process_existing_user(api_response)
                     else
                       {
                         error: true,
                         status_code: api_response.status,
                         response_body: api_response.body
                       }
                     end
    rescue StandardError => e
      raise Tasker::PermanentError,
            "Failed to process user registration results: #{e.message}"
    end

    private

    def extract_and_validate_inputs(task, _sequence, _step)
      context = task.context.deep_symbolize_keys
      user_info = context[:user_info] || {}

      # Validate required fields
      email = user_info[:email]
      unless email&.include?('@')
        raise Tasker::PermanentError.new(
          'Valid email is required for user registration',
          error_code: 'INVALID_EMAIL'
        )
      end

      name = user_info[:name]
      unless name && !name.strip.empty?
        raise Tasker::PermanentError.new(
          'Name is required for user registration',
          error_code: 'MISSING_NAME'
        )
      end

      {
        email: email.downcase.strip,
        name: name.strip,
        phone: user_info[:phone],
        plan: user_info[:plan] || 'free',
        marketing_consent: context[:preferences]&.dig(:marketing_emails) || false
      }
    end

    def register_user_via_api(inputs)
      # Make HTTP API call with proper error handling
      response = connection.post('/users', inputs)

      # Log API call for debugging
      Rails.logger.debug { "User API response: #{response.status} - #{response.body[0..200]}" }

      response
    rescue Faraday::TimeoutError => e
      raise Tasker::RetryableError, "User service timeout: #{e.message}"
    rescue Faraday::ConnectionFailed => e
      raise Tasker::RetryableError, "User service connection failed: #{e.message}"
    end

    def handle_api_response(response, inputs)
      case response.status
      when 201
        # User created successfully
        response
      when 409
        # User already exists - check for idempotency
        check_user_idempotency(response, inputs)
        response
      when 400
        raise Tasker::PermanentError.new(
          'Invalid user registration data',
          error_code: 'INVALID_USER_DATA'
        )
      when 429
        raise Tasker::RetryableError.new(
          'User service rate limited',
          retry_after: 30
        )
      when 500, 502, 503, 504
        raise Tasker::RetryableError, 'User service temporarily unavailable'
      else
        raise Tasker::RetryableError, "Unexpected user service response: #{response.status}"
      end
    end

    def check_user_idempotency(response, inputs)
      # Parse conflict response to check if it's idempotent

      existing_user = JSON.parse(response.body).deep_symbolize_keys

      if user_matches_inputs?(existing_user, inputs)
        Rails.logger.info "User already exists with matching data: #{inputs[:email]}"
      else
        raise Tasker::PermanentError.new(
          "User #{inputs[:email]} exists with conflicting data",
          error_code: 'USER_CONFLICT'
        )
      end
    rescue JSON::ParserError
      raise Tasker::PermanentError,
            'Unable to parse user conflict response'
    end

    def user_matches_inputs?(existing_user, inputs)
      # Define what constitutes a match for idempotency
      existing_user[:email] == inputs[:email] &&
        existing_user[:name] == inputs[:name] &&
        existing_user[:plan] == inputs[:plan]
    end

    def process_successful_registration(response)
      user_data = JSON.parse(response.body).deep_symbolize_keys

      {
        user_id: user_data[:id],
        email: user_data[:email],
        status: 'created',
        created_at: user_data[:created_at],
        registration_timestamp: Time.current.iso8601
      }
    end

    def process_existing_user(response)
      user_data = JSON.parse(response.body).deep_symbolize_keys

      {
        user_id: user_data[:id],
        email: user_data[:email],
        status: 'already_exists',
        created_at: user_data[:created_at],
        registration_timestamp: Time.current.iso8601
      }
    end

    # NOTE: Configuration in YAML step template:
    # step_templates:
    #   - name: register_user
    #     handler_class: "UserRegistrationHandler"
    #     default_retry_limit: 3              # Step template level
    #     default_retryable: true             # Step template level
    #     handler_config:                     # API config level
    #       url: "http://user-service.example.com"
    #       retry_delay: 1.0
    #       enable_exponential_backoff: true
  end

  # Example 3: Cross-Namespace Coordination Handler
  # Demonstrates: Team coordination, data mapping, correlation tracking
  class CrossTeamWorkflowHandler < Tasker::StepHandler::Api
    def process(task, sequence, step)
      # Phase 1: Extract and validate inputs with team-specific data mapping
      inputs = extract_and_validate_inputs(task, sequence, step)

      Rails.logger.info "Delegating to #{inputs[:target_namespace]}: #{inputs[:workflow_name]}"

      # Phase 2: Execute business logic (cross-team API call)
      response = delegate_to_target_team(inputs)

      # Phase 3: Validate delegation response
      ensure_delegation_successful!(response)

      response
    end

    def process_results(step, delegation_response, _initial_results)
      # Phase 4: Format delegation results with correlation tracking

      parsed_response = if delegation_response.respond_to?(:body)
                          JSON.parse(delegation_response.body).deep_symbolize_keys
                        else
                          delegation_response.deep_symbolize_keys
                        end

      step.results = {
        task_delegated: true,
        target_namespace: parsed_response[:namespace],
        target_workflow: parsed_response[:workflow_name],
        delegated_task_id: parsed_response[:task_id],
        delegated_task_status: parsed_response[:status],
        correlation_id: parsed_response[:correlation_id],
        delegation_timestamp: Time.current.iso8601
      }
    rescue JSON::ParserError => e
      raise Tasker::PermanentError,
            "Failed to parse delegation response: #{e.message}"
    rescue StandardError => e
      raise Tasker::PermanentError,
            "Failed to process delegation results: #{e.message}"
    end

    private

    def extract_and_validate_inputs(task, sequence, _step)
      context = task.context.deep_symbolize_keys

      # Validate delegation target
      target_namespace = context[:target_namespace]
      unless target_namespace
        raise Tasker::PermanentError.new(
          'Target namespace is required for delegation',
          error_code: 'MISSING_TARGET_NAMESPACE'
        )
      end

      # Get prerequisite results from previous steps
      approval_step = sequence.find_step_by_name('get_approval')
      approval_results = approval_step&.results&.deep_symbolize_keys

      unless approval_results&.dig(:approved)
        raise Tasker::PermanentError,
              'Approval must be obtained before delegation'
      end

      # Map current team's data to target team's expected format
      {
        target_namespace: target_namespace,
        workflow_name: context[:target_workflow] || 'process_request',
        workflow_version: context[:target_version] || '1.0.0',
        context: map_context_for_target_team(context, approval_results),
        correlation_id: context[:correlation_id] || generate_correlation_id
      }
    end

    def map_context_for_target_team(context, approval_results)
      # Transform current team's data model to target team's expectations
      {
        request_id: context[:ticket_id] || context[:request_id],
        customer_id: context[:customer_id],
        amount: context[:amount],
        reason: context[:reason] || context[:description],
        initiated_by: determine_initiating_team,
        approval_id: approval_results[:approval_id],
        correlation_id: context[:correlation_id] || generate_correlation_id,
        metadata: {
          original_context: context.except(:sensitive_data),
          delegation_timestamp: Time.current.iso8601
        }
      }
    end

    def delegate_to_target_team(inputs)
      # Make cross-team API call
      response = connection.post('/tasker/tasks', inputs)

      Rails.logger.debug { "Delegation response: #{response.status}" }

      response
    rescue Faraday::TimeoutError => e
      raise Tasker::RetryableError, "Target team service timeout: #{e.message}"
    rescue Faraday::ConnectionFailed => e
      raise Tasker::RetryableError, "Target team service unavailable: #{e.message}"
    end

    def ensure_delegation_successful!(response)
      case response.status
      when 201, 200
        # Check response body for actual task creation status
        parsed_response = JSON.parse(response.body).deep_symbolize_keys

        case parsed_response[:status]
        when 'created', 'queued'
          unless parsed_response[:task_id]
            raise Tasker::PermanentError,
                  'Task delegated but no task ID returned'
          end
        when 'rejected'
          raise Tasker::PermanentError,
                "Delegation rejected: #{parsed_response[:reason]}"
        else
          raise Tasker::RetryableError,
                "Unexpected delegation status: #{parsed_response[:status]}"
        end
      when 400
        raise Tasker::PermanentError, 'Invalid delegation request'
      when 403
        raise Tasker::PermanentError, 'Not authorized for cross-team delegation'
      when 404
        raise Tasker::PermanentError, 'Target workflow not found'
      when 429
        raise Tasker::RetryableError, 'Target team rate limited'
      when 500, 502, 503, 504
        raise Tasker::RetryableError, 'Target team service unavailable'
      else
        raise Tasker::RetryableError, "Unexpected delegation response: #{response.status}"
      end
    end

    def determine_initiating_team
      # Determine which team is making the delegation
      self.class.module_parent.name.underscore
    end

    def generate_correlation_id
      # Generate team-specific correlation ID
      team_prefix = determine_initiating_team.split('_').first
      "#{team_prefix}-#{SecureRandom.hex(8)}"
    end

    # NOTE: Configuration in YAML step template:
    # step_templates:
    #   - name: delegate_workflow
    #     handler_class: "CrossTeamWorkflowHandler"
    #     default_retry_limit: 2              # Step template level
    #     default_retryable: true             # Step template level
    #     handler_config:                     # API config level
    #       url: "http://tasker-api.example.com"
    #       retry_delay: 2.0
    #       enable_exponential_backoff: true
  end
end

# Example usage in tests:
#
# RSpec.describe StepHandlerExamples::BasicComputationHandler do
#   let(:handler) { described_class.new }
#
#   it 'calculates shipping costs correctly' do
#     result = handler.process(mock_task, mock_sequence, mock_step)
#     expect(result[:cost]).to be > 0
#   end
# end
