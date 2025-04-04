# frozen_string_literal: true

require 'faraday'
module Tasker
  module StepHandler
    class Api < Base
      attr_reader :connection, :config

      BACKOFF_ERROR_CODES = [429, 503].freeze
      SUCCESS_CODES = (200..226)

      class Config
        attr_accessor :url, :params, :ssl, :headers, :retry_delay, :enable_exponential_backoff, :jitter_factor

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

        def default_headers
          {
            'Content-Type' => 'application/json',
            'Accept' => 'application/json'
          }
        end
      end

      def initialize(config: Config.new, &)
        super(config: config)
        @connection = _build_connection(&)
      end

      def handle(task, sequence, step)
        response = call(task, sequence, step)
        _process_response(step, response)
        step.results = response
      rescue Faraday::Error => e
        _handle_too_many_requests(step, e.response) if e.response && BACKOFF_ERROR_CODES.include?(e.response&.status)
        raise
      end

      def call(task, sequence, step)
        # Example from the Faraday docs:
        #
        # response = connection.post('post', { payload: 'this ruby hash will become JSON' })
        #
        # Where connection is a Faraday::Connection object
        # and the parameters are likely derived from the task, step sequence, and step data
        raise NotImplementedError, 'Subclasses must implement this method'
      end

      private

      def _process_response(step, response)
        status = response.is_a?(Hash) ? response[:status] : response.status
        return unless SUCCESS_CODES.exclude?(status) && BACKOFF_ERROR_CODES.include?(status)

        _handle_too_many_requests(step, response)
        raise Faraday::Error, "API call failed with status #{status} and body #{response.body}"
      end

      def _handle_too_many_requests(step, response)
        retry_after = response.headers['Retry-After']
        if retry_after
          step.backoff_request_seconds = _parse_retry_after(retry_after)
        elsif @config.enable_exponential_backoff
          _exponential_backoff(step)
        end
      end

      def _parse_retry_after(retry_after)
        if retry_after.match?(/^\d+$/)
          retry_after.to_i
        else
          (retry_after.to_time - Time.zone.now).to_i
        end
      rescue StandardError => e
        raise Faraday::Error, "Failed to parse Retry-After header: #{e.message}"
      end

      def _exponential_backoff(step)
        step.attempts ||= 1
        min_exponent = 2
        exponent = [step.attempts + 1, min_exponent].max
        # Standard exponential backoff formula: base_delay * (2 ^ attempt)
        # Starting with attempt=1, this gives: base_delay, 2*base_delay, 4*base_delay, 8*base_delay, etc.
        base_delay = @config.retry_delay || 1.0 # Default to 1 second if not specified

        # Calculate exponential delay with a cap to prevent excessive waiting
        max_delay = 30.0 # Cap maximum delay at 30 seconds
        exponential_delay = [base_delay * (2**exponent), max_delay].min

        # Add jitter (randomness) to prevent thundering herd problem
        # Use full jitter algorithm: random value between 0 and exponential_delay
        jitter_factor = @config.jitter_factor
        retry_delay = exponential_delay * jitter_factor

        # Ensure minimum delay of at least half the base delay
        retry_delay = [retry_delay, base_delay * 0.5].max

        step.backoff_request_seconds = retry_delay
        step.last_attempted_at = Time.zone.now
      end

      def _build_connection(&)
        Faraday.new(
          url: @config.url,
          params: @config.params,
          headers: @config.headers,
          ssl: @config.ssl,
          &
        )
      end
    end
  end
end
