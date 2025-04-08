# frozen_string_literal: true

module Tasker
  class Railtie < ::Rails::Railtie
    initializer 'tasker.load_telemetry' do
      # Load the base lifecycle and telemetry modules
      require 'tasker/lifecycle_events'
      require 'tasker/telemetry'
      require 'tasker/telemetry/adapter'
      require 'tasker/telemetry/logger_adapter'

      # Only require OpenTelemetry if it's enabled in the configuration
      if defined?(Tasker.configuration) &&
         Tasker.configuration.enable_telemetry &&
         Array(Tasker.configuration.telemetry_adapters).include?(:opentelemetry)
        begin
          require 'tasker/telemetry/opentelemetry_adapter'
        rescue LoadError => e
          Rails.logger.error "Could not load OpenTelemetry adapter: #{e.message}"
          Rails.logger.error "Please add 'opentelemetry-sdk' and 'opentelemetry-instrumentation-all' to your Gemfile"

          # Replace opentelemetry with default in the adapters list
          Tasker.configuration.telemetry_adapters = Array(Tasker.configuration.telemetry_adapters).map do |adapter|
            adapter == :opentelemetry ? :default : adapter
          end
        end
      end

      # Initialize telemetry (which will register the observer)
      Tasker::Telemetry.initialize
    end
  end
end
