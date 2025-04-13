# frozen_string_literal: true

require 'active_model_serializers'
require 'graphql'
require 'json-schema'
require 'pg'
# typed: strict

require 'rails'
require 'sorbet-runtime'

module Tasker
  class Engine < ::Rails::Engine
    isolate_namespace Tasker

    # Configure paths before initialization
    config.before_configuration do |app|
      app.config.autoload_paths << root.join('lib')
      app.config.eager_load_paths << root.join('lib')
    end

    # Initialize components before app initialization
    initializer 'tasker.setup', before: :load_config_initializers do |_app|
      # Load required components
      require 'dry-types'
      require 'dry-struct'
      require 'tasker/configuration'
      require 'tasker/constants'
      require 'tasker/handler_factory'
      require 'tasker/types'
      require 'tasker/task_handler'
      require 'tasker/task_builder'
      require 'tasker/identity_strategy'
      require 'tasker/lifecycle_events'
      require 'tasker/instrumentation'
      require 'tasker/railtie'

      # Configure generators
      config.generators.api_only = true
      config.generators.test_framework = :rspec
      config.application_controller = 'ActionController::API'
    end

    class << self
      extend T::Sig

      sig { params(_block: T.proc.params(config: Rails::Configuration).void).void }
      def configure(&)
        yield(Engine.config)
      end
    end
  end
end
