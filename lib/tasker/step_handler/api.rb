# frozen_string_literal: true

require 'faraday'
require_relative '../concerns/event_publisher'
require_relative '../orchestration/response_processor'
require_relative '../orchestration/backoff_calculator'
require_relative '../orchestration/connection_builder'

module Tasker
  module StepHandler
    # Handles API-based workflow steps by making HTTP requests
    # and processing responses with backoff/retry support
    #
    # @example Creating a custom API step handler
    #   class MyApiHandler < Tasker::StepHandler::Api
    #     def process(task, sequence, step)
    #       connection.post('/endpoint', task.context)
    #     end
    #   end
    class Api < Base
      include Tasker::Concerns::EventPublisher

      # @return [Faraday::Connection] The Faraday connection for making HTTP requests
      attr_reader :connection

      # @return [Config] The configuration for this API handler
      attr_reader :config

      # Configuration class for API step handlers
      class Config
        # @return [String] The base URL for API requests
        attr_accessor :url

        # @return [Hash] The default query parameters for requests
        attr_accessor :params

        # @return [Hash, nil] SSL configuration options
        attr_accessor :ssl

        # @return [Hash] Request headers
        attr_accessor :headers

        # @return [Float] Delay in seconds before retrying after failure
        attr_accessor :retry_delay

        # @return [Boolean] Whether to use exponential backoff for retries
        attr_accessor :enable_exponential_backoff

        # @return [Float] Random factor for jitter calculation (0.0-1.0)
        attr_accessor :jitter_factor

        # Creates a new API configuration
        #
        # @param url [String] The base URL for API requests
        # @param params [Hash] Query parameters for requests
        # @param ssl [Hash, nil] SSL configuration options
        # @param headers [Hash] Request headers
        # @param enable_exponential_backoff [Boolean] Whether to use exponential backoff
        # @param retry_delay [Float] Delay in seconds before retrying
        # @param jitter_factor [Float] Random factor for jitter calculation
        # @return [Config] A new configuration instance
        def initialize(
          url:,
          params: {},
          ssl: nil,
          headers: default_headers,
          enable_exponential_backoff: true,
          retry_delay: 1.0,
          jitter_factor: rand
        )
          @url = url
          @params = params
          @ssl = ssl
          @headers = headers
          @enable_exponential_backoff = enable_exponential_backoff
          @retry_delay = retry_delay
          @jitter_factor = jitter_factor
        end

        # Returns the default headers for API requests
        #
        # @return [Hash] The default headers
        def default_headers
          {
            'Content-Type' => 'application/json',
            'Accept' => 'application/json'
          }
        end
      end

      # Creates a new API step handler
      #
      # @param config [Config] The configuration for this handler
      # @yield [Faraday::Connection] Optional block for configuring the Faraday connection
      # @return [Api] A new API step handler
      def initialize(config: Config.new, &connection_block)
        super(config: config)

        # Initialize orchestration components
        @response_processor = Tasker::Orchestration::ResponseProcessor.new
        @backoff_calculator = Tasker::Orchestration::BackoffCalculator.new(config: config)
        @connection_builder = Tasker::Orchestration::ConnectionBuilder.new

        # Build connection using orchestration component
        @connection = @connection_builder.build_connection(config, &connection_block)
      end

      # Framework coordination method for API step handlers
      #
      # ⚠️  NEVER OVERRIDE THIS METHOD - Framework-only code
      # This method coordinates the API-specific workflow around the developer's process() method
      #
      # @param task [Tasker::Task] The task being executed
      # @param sequence [Tasker::Types::StepSequence] The sequence of steps
      # @param step [Tasker::WorkflowStep] The current step being handled
      # @return [void]
      def handle(task, sequence, step)
        # Publish step started event
        publish_step_started(step)

        # Fire the before_handle event for compatibility (matches base class pattern)
        publish_step_before_handle(step)

        begin
          response = execute_api_workflow(task, sequence, step)
          publish_step_completed(step)
          response
        rescue StandardError => e
          handle_execution_error(step, e)
          raise
        end
      end

      # Developer extension point for API step handlers
      #
      # ✅  IMPLEMENT THIS METHOD: This is your extension point for API business logic
      #
      # This is where you implement your specific HTTP request logic.
      # Use the provided connection object to make requests and return the response.
      #
      # The framework will automatically:
      # - Publish step_started before calling this method
      # - Handle response processing, error detection, and backoff
      # - Publish step_completed after this method succeeds
      # - Publish step_failed if this method raises an exception
      #
      # Examples:
      #   def process(task, sequence, step)
      #     user_id = task.context['user_id']
      #     connection.get("/users/#{user_id}")
      #   end
      #
      #   def process(task, sequence, step)
      #     connection.post('/orders', task.context)
      #   end
      #
      # @param task [Tasker::Task] The task being executed
      # @param sequence [Tasker::Types::StepSequence] The sequence of steps
      # @param step [Tasker::WorkflowStep] The current step being handled
      # @return [Faraday::Response, Hash] The API response
      def process(task, sequence, step)
        raise NotImplementedError, 'API step handler subclasses must implement the process method to make HTTP requests'
      end

      private

      # Execute the main API workflow with orchestration
      #
      # @param task [Tasker::Task] The task being executed
      # @param sequence [Tasker::Types::StepSequence] The sequence of steps
      # @param step [Tasker::WorkflowStep] The current step being handled
      # @return [Object] The API response
      def execute_api_workflow(task, sequence, step)
        Rails.logger.debug { "StepHandler: Starting execution of step #{step.workflow_step_id} (#{step.name})" }

        # Store initial results state to detect if developer set them
        initial_results = step.results

        # Call the developer-implemented process() method to make the HTTP request
        response = process(task, sequence, step)

        # Process response and handle any API-specific error conditions
        handle_api_response(step, response)

        # Set results using overridable method, respecting developer customization
        process_results(step, response, initial_results)

        Rails.logger.debug { "StepHandler: Completed execution of step #{step.workflow_step_id} (#{step.name})" }
        response
      end

      # Handle API response processing and error detection
      #
      # @param step [Tasker::WorkflowStep] The current step
      # @param response [Object] The API response to process
      # @raise [Faraday::Error] If response indicates a failure requiring backoff
      def handle_api_response(step, response)
        error_context = @response_processor.process_response(step, response)

        return unless error_context

        # Apply backoff for error responses that require it
        @backoff_calculator.calculate_and_apply_backoff(step, error_context)

        # Raise error with response details for proper error handling
        body = extract_error_body(error_context[:response])
        raise Faraday::Error, "API call failed with status #{error_context[:status]} and body #{body}"
      end

      # Handle errors that occur during step execution
      #
      # @param step [Tasker::WorkflowStep] The current step
      # @param error [StandardError] The error that occurred
      def handle_execution_error(step, error)
        # Apply backoff for specific Faraday errors
        if error.is_a?(Faraday::Error) && error.response && backoff_error_code?(error.response.status)
          error_context = build_faraday_error_context(step, error.response)
          @backoff_calculator.calculate_and_apply_backoff(step, error_context)
        end

        # Add error information to results using the same extensible pattern
        add_error_to_results(step, error)

        # Publish step failed event with error information
        publish_step_failed(step, error: error)
      end

      # Extract error body from response for error messages
      #
      # @param response [Object] The response object
      # @return [String] The response body
      def extract_error_body(response)
        response.is_a?(Hash) ? response[:body] : response.body
      end

      # Check if status code requires backoff handling
      #
      # @param status [Integer] HTTP status code
      # @return [Boolean] True if status requires backoff
      def backoff_error_code?(status)
        [429, 503].include?(status)
      end

      # Build error context for Faraday errors
      #
      # @param step [Tasker::WorkflowStep] The current step
      # @param response [Faraday::Response] The error response
      # @return [Hash] Context for backoff handling
      def build_faraday_error_context(step, response)
        {
          step_id: step.workflow_step_id,
          step_name: step.name,
          status: response.status,
          response: response,
          headers: response.headers
        }
      end

      # Process the output from process() method and store in step.results
      #
      # ✅ OVERRIDE THIS METHOD: To customize how process() output is stored
      #
      # This method provides a clean extension point for customizing how the response
      # from your process() method gets stored in step.results. The default behavior
      # is to store the raw response, but you can override this to transform the data.
      #
      # @param step [Tasker::WorkflowStep] The current step
      # @param process_output [Object] The return value from process() method
      # @param initial_results [Object] The value of step.results before process() was called
      # @return [void]
      def process_results(step, process_output, initial_results)
        # If developer already set step.results in their process() method, respect it
        if step.results != initial_results
          Rails.logger.debug do
            'StepHandler: Developer set custom results in process() method - respecting custom results'
          end
          return
        end

        # Default behavior: store the raw response from process()
        step.results = process_output
      end

      # Add error information to step results
      #
      # ✅ OVERRIDE THIS METHOD: To customize how error information is stored
      #
      # This method provides a clean extension point for customizing how error
      # information gets added to step.results. The default behavior ensures
      # results is a hash and adds error details.
      #
      # @param step [Tasker::WorkflowStep] The current step
      # @param error [StandardError] The error that occurred
      # @return [void]
      def add_error_to_results(step, error)
        # Ensure results is a hash so we can add error information
        current_results = step.results || {}

        # If results is not a hash (e.g., Faraday::Response), convert it
        unless current_results.is_a?(Hash)
          current_results = {
            original_response: current_results,
            response_type: current_results.class.name
          }
        end

        # Add error information
        error_info = {
          error_message: error.message,
          error_class: error.class.name,
          backtrace: error.backtrace&.first(10)
        }

        # Add response details for Faraday errors
        if error.is_a?(Faraday::Error) && error.response
          error_info[:response_status] = error.response.status
          error_info[:response_body] = error.response.body
        end

        step.results = current_results.merge(
          error: true,
          error_details: error_info
        )
      end
    end
  end
end
