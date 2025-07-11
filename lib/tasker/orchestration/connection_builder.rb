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
            "with #{config.params} params and #{config.headers} headers"
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
        ConfigValidator.validate(config)
      end

      # Service class to validate connection configuration
      # Reduces complexity by organizing validation logic
      class ConfigValidator
        class << self
          # Validate configuration object
          #
          # @param config [Object] Configuration to validate
          # @raise [ArgumentError] If configuration is invalid
          def validate(config)
            validate_config_presence(config)
            validate_config_interface(config)
            validate_url_presence(config)
            validate_url_format(config)
          end

          private

          # Validate configuration is present
          #
          # @param config [Object] Configuration to validate
          # @raise [ArgumentError] If configuration is nil
          def validate_config_presence(config)
            raise ArgumentError, 'Configuration cannot be nil' if config.nil?
          end

          # Validate configuration has required interface
          #
          # @param config [Object] Configuration to validate
          # @raise [ArgumentError] If configuration doesn't respond to :url
          def validate_config_interface(config)
            raise ArgumentError, 'Configuration must respond to :url' unless config.respond_to?(:url)
          end

          # Validate URL is present and non-empty
          #
          # @param config [Object] Configuration to validate
          # @raise [ArgumentError] If URL is nil or empty
          def validate_url_presence(config)
            return unless config.url.nil? || config.url.strip.empty?

            raise ArgumentError, 'Configuration URL cannot be nil or empty'
          end

          # Validate URL format using URI parsing
          #
          # @param config [Object] Configuration to validate
          # @raise [ArgumentError] If URL format is invalid
          def validate_url_format(config)
            uri = URI.parse(config.url)
            validate_uri_components(uri)
          rescue URI::InvalidURIError => e
            raise ArgumentError, "Configuration URL is not a valid URI: #{e.message}"
          end

          # Validate URI has required components
          #
          # @param uri [URI] Parsed URI to validate
          # @raise [ArgumentError] If URI lacks scheme or host
          def validate_uri_components(uri)
            return if uri.scheme && uri.host

            raise ArgumentError, 'Configuration URL must be a valid URI with scheme and host'
          end
        end
      end
    end
  end
end
