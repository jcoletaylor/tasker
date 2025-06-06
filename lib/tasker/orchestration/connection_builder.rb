# frozen_string_literal: true

require 'faraday'

module Tasker
  module Orchestration
    # ConnectionBuilder handles Faraday connection configuration and building
    #
    # This component provides focused responsibility for building and configuring
    # Faraday connections based on API handler configuration, with support for
    # custom connection block configuration.
    class ConnectionBuilder
      # Build a Faraday connection from configuration
      #
      # @param config [Object] Configuration object with connection settings
      # @yield [Faraday::Connection] Optional block for custom connection configuration
      # @return [Faraday::Connection] Configured Faraday connection
      def build_connection(config, &connection_block)
        validate_config(config)

        Rails.logger.debug do
          "ConnectionBuilder: Building connection to #{config.url} " \
            "with #{config.params.keys.size} params and #{config.headers.keys.size} headers"
        end

        connection = Faraday.new(
          url: config.url,
          params: config.params || {},
          headers: config.headers || {},
          ssl: config.ssl
        )

        # Apply custom configuration block if provided
        if connection_block
          Rails.logger.debug('ConnectionBuilder: Applying custom connection configuration')
          yield(connection)
        end

        connection
      rescue StandardError => e
        Rails.logger.error(
          "ConnectionBuilder: Failed to build connection to #{config&.url}: #{e.message}"
        )
        raise
      end

      # Validate configuration has required fields
      #
      # @param config [Object] Configuration to validate
      # @raise [ArgumentError] If configuration is invalid
      def validate_config(config)
        raise ArgumentError, 'Configuration cannot be nil' if config.nil?

        raise ArgumentError, 'Configuration must respond to :url' unless config.respond_to?(:url)

        raise ArgumentError, 'Configuration URL cannot be nil or empty' if config.url.nil? || config.url.strip.empty?

        # Validate URL format
        begin
          uri = URI.parse(config.url)
          unless uri.scheme && uri.host
            raise ArgumentError, 'Configuration URL must be a valid URI with scheme and host'
          end
        rescue URI::InvalidURIError => e
          raise ArgumentError, "Configuration URL is not a valid URI: #{e.message}"
        end
      end
    end
  end
end
