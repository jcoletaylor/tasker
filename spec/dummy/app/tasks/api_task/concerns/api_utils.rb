# frozen_string_literal: true

module ApiTask
  module ApiUtils
    def get_from_results(results, key)
      results = results.deep_symbolize_keys if results.respond_to?(:deep_symbolize_keys)

      ResponseParser.parse(results, key)
    rescue JSON::ParserError => e
      Rails.logger.error("Error parsing JSON in get_from_results: #{e.message}")
      { key => nil, error: e.message }
    rescue StandardError => e
      Rails.logger.error("Error getting key #{key} from results: #{e.message}")
      { key => nil, error: e.message }
    end

    # Service class to parse different response structures
    # Reduces complexity by organizing response parsing logic
    class ResponseParser
      class << self
        # Parse response and extract key value
        #
        # @param results [Hash, Object] The response object to parse
        # @param key [String, Symbol] The key to extract
        # @return [Hash] Parsed response with key or error
        def parse(results, key)
          if nested_status_response?(results)
            parse_nested_status_response(results, key)
          elsif faraday_response?(results)
            parse_faraday_response(results, key)
          else
            parse_unknown_response(key)
          end
        end

        private

        # Check if response has nested status structure
        #
        # @param results [Object] Response to check
        # @return [Boolean] True if has nested status structure
        def nested_status_response?(results)
          results.is_a?(Hash) && results.dig(:status, :status)
        end

        # Check if response is a Faraday::Response object
        #
        # @param results [Object] Response to check
        # @return [Boolean] True if is Faraday response
        def faraday_response?(results)
          results.respond_to?(:status) && results.respond_to?(:body)
        end

        # Parse nested status response structure
        #
        # @param results [Hash] Response hash
        # @param key [String, Symbol] Key to extract
        # @return [Hash] Parsed response
        def parse_nested_status_response(results, key)
          status_code = results.dig(:status, :status)
          body_content = results.dig(:status, :body)

          if status_code == 200
            { key => JSON.parse(body_content)&.dig(key) }
          else
            { error: JSON.parse(body_content)&.dig('error') }
          end
        end

        # Parse Faraday::Response object
        #
        # @param results [Faraday::Response] Response object
        # @param key [String, Symbol] Key to extract
        # @return [Hash] Parsed response
        def parse_faraday_response(results, key)
          if results.status == 200
            { key => JSON.parse(results.body)&.dig(key) }
          else
            { error: JSON.parse(results.body)&.dig('error') }
          end
        end

        # Handle unknown response structure
        #
        # @param key [String, Symbol] Key being requested
        # @return [Hash] Error response for unknown structure
        def parse_unknown_response(key)
          { key => nil, error: 'Unknown response structure' }
        end
      end
    end
  end
end
