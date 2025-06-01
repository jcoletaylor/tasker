# frozen_string_literal: true

module ApiTask
  module ApiUtils
    def get_from_results(results, key)
      results = results.deep_symbolize_keys if results.respond_to?(:deep_symbolize_keys)

      # Handle success case - nested structure with :status hash
      if results.is_a?(Hash) && results.dig(:status, :status)
        status_code = results.dig(:status, :status)
        body_content = results.dig(:status, :body)

        if status_code == 200
          { key => JSON.parse(body_content)&.dig(key) }
        else
          { error: JSON.parse(body_content)&.dig('error') }
        end
      # Handle error case - direct Faraday::Response object
      elsif results.respond_to?(:status) && results.respond_to?(:body)
        if results.status == 200
          { key => JSON.parse(results.body)&.dig(key) }
        else
          { error: JSON.parse(results.body)&.dig('error') }
        end
      # Fallback for unexpected structure
      else
        { key => nil, error: 'Unknown response structure' }
      end
    rescue JSON::ParserError => e
      logger.error("Error parsing JSON in get_from_results: #{e.message}")
      { key => nil, error: e.message }
    rescue StandardError => e
      logger.error("Error getting key #{key} from results: #{e.message}")
      { key => nil, error: e.message }
    end
  end
end
