# frozen_string_literal: true

module Tasker
  class Railtie < ::Rails::Railtie
    initializer 'tasker.load_observability', after: :load_config_initializers do
      # Legacy instrumentation removed - using TelemetrySubscriber instead
    end
  end
end
