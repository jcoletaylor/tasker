# frozen_string_literal: true

module Tasker
  module Orchestration
    # RetryHeaderParser handles parsing and validation of HTTP Retry-After headers
    #
    # This component provides focused responsibility for parsing Retry-After headers
    # according to HTTP specification, handling both seconds-based and date-based formats.
    class RetryHeaderParser
      # Parse a Retry-After header value into seconds
      #
      # The Retry-After header can contain either:
      # - An integer representing seconds (e.g., "120")
      # - An HTTP date (e.g., "Wed, 21 Oct 2015 07:28:00 GMT")
      #
      # @param retry_after [String] The Retry-After header value
      # @return [Integer] Number of seconds to wait before retrying
      # @raise [Faraday::Error] If the header value cannot be parsed
      def parse_retry_after(retry_after)
        return 0 if retry_after.nil? || retry_after.strip.empty?

        # Handle seconds-based format (just digits)
        if retry_after.match?(/^\d+$/)
          seconds = retry_after.to_i
          validate_retry_seconds(seconds)
          return seconds
        end

        # Handle HTTP date format
        parse_http_date_retry_after(retry_after)
      rescue StandardError => e
        Rails.logger.error(
          "RetryHeaderParser: Failed to parse Retry-After header '#{retry_after}': #{e.message}"
        )
        raise Faraday::Error, "Failed to parse Retry-After header: #{e.message}"
      end

      private

      # Parse HTTP date format Retry-After header
      #
      # @param retry_after [String] The Retry-After header in HTTP date format
      # @return [Integer] Number of seconds to wait
      def parse_http_date_retry_after(retry_after)
        retry_time = Time.zone.parse(retry_after)
        seconds = (retry_time - Time.zone.now).to_i

        # Ensure we don't get negative wait times
        seconds = [seconds, 0].max

        validate_retry_seconds(seconds)
        seconds
      end

      # Validate that retry seconds are within reasonable bounds
      #
      # @param seconds [Integer] Number of seconds to validate
      # @raise [Faraday::Error] If seconds are outside reasonable bounds
      def validate_retry_seconds(seconds)
        # Set reasonable bounds for retry delays
        max_retry_seconds = 3600 # 1 hour maximum

        if seconds > max_retry_seconds
          Rails.logger.warn(
            "RetryHeaderParser: Retry-After header requests #{seconds} seconds, " \
            "capping at #{max_retry_seconds} seconds"
          )
          # Don't raise an error, just log and cap the value
          # The caller will get the capped value when we return it
        end

        return unless seconds.negative?

        raise Faraday::Error, "Retry-After header resulted in negative wait time: #{seconds}"
      end
    end
  end
end
