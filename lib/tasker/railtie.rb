# frozen_string_literal: true

module Tasker
  class Railtie < ::Rails::Railtie
    initializer 'tasker.load_observability', after: :load_config_initializers do
      # Load the base instrumentation module
      require 'tasker/instrumentation'
      Tasker::Instrumentation.subscribe
    end
  end
end
