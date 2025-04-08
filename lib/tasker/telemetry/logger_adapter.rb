# frozen_string_literal: true

module Tasker
  module Telemetry
    # Default adapter implementation using Rails.logger
    class LoggerAdapter < Adapter
      # Record an event with the given payload
      # @param event [String] The name of the event
      # @param payload [Hash] The payload data to record
      def record(event, payload = {})
        logger.info "[Tasker] #{event}: #{payload.to_json}"
      end

      private

      def logger
        Rails.logger
      end
    end
  end
end
