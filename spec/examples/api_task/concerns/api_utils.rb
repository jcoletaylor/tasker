# frozen_string_literal: true

module ApiTask
  module ApiUtils
    def get_from_results(results, key)
      results = results.deep_symbolize_keys
      if results.dig(:status, :status) == 200
        { key => JSON.parse(results.dig(:status, :body))&.dig(key) }
      else
        { error: JSON.parse(results.dig(:status, :body))&.dig('error') }
      end
    rescue StandardError => e
      logger.error("Error getting key #{key} from results: #{e.message}")
      { key => nil, error: e.message }
    end
  end
end
