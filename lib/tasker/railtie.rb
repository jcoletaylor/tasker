# frozen_string_literal: true

module Tasker
  class Railtie < ::Rails::Railtie
    initializer 'tasker.load_observability' do
      # Load the base lifecycle and observability modules
      require 'tasker/lifecycle_events'
      require 'tasker/observability/adapter'
      require 'tasker/observability/logger_adapter'
      require 'tasker/observability/open_telemetry_adapter'
      require 'tasker/observability/lifecycle_observer'

      # Initialize the observability configuration and register observers
      Tasker.configuration.observability.register_observer!
    end
  end
end
