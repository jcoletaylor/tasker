# frozen_string_literal: true

# Rails engine for Tasker gem
#
# This engine handles Rails-specific setup, autoloading configuration,
# and loading of production runtime components. Development/test-only
# dependencies are handled by the Gemfile and should not be loaded here.

# Required Rails framework
require 'rails'

# Runtime dependencies from gemspec that need explicit loading
require 'active_model_serializers'
require 'graphql'
require 'json-schema'
require 'pg'
require 'faraday'
require 'scenic'

module Tasker
  class Engine < ::Rails::Engine
    isolate_namespace Tasker

    # Configure paths before initialization to let Zeitwerk handle autoloading
    config.before_configuration do |app|
      app.config.autoload_paths << root.join('lib')
      app.config.eager_load_paths << root.join('lib')
    end

    # Initialize essential components before app initialization
    initializer 'tasker.setup', before: :load_config_initializers do |_app|
      # Load core components that need explicit initialization
      require 'tasker/constants'
      require 'tasker/configuration'
      # Legacy instrumentation removed - using TelemetrySubscriber instead
      require 'tasker/types'
      require 'tasker/handler_factory'
      require 'tasker/identity_strategy'
      require 'tasker/task_handler'
      require 'tasker/task_builder'
      require 'tasker/state_machine'
      require 'tasker/orchestration'
      require 'tasker/events'
      require 'tasker/events/publisher'
      require 'tasker/events/catalog'
      require 'tasker/events/subscribers/base_subscriber'
      require 'tasker/events/subscribers/telemetry_subscriber'

      # Configure Statesman for state machine support
      Tasker::StateMachine.configure_statesman

      # Configure generators for Rails integration
      config.generators.api_only = true
      config.generators.test_framework = :rspec
      config.application_controller = 'ActionController::API'
    end

    # Initialize orchestration system after Rails is fully loaded
    initializer 'tasker.orchestration', after: :load_config_initializers do |_app|
      # Initialize the orchestration system in all environments
      # This ensures consistent behavior between test, development, and production
      Tasker::Orchestration::Coordinator.initialize!
    end

    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :factory_bot
      g.factory_bot dir: 'spec/factories'
    end

    class << self
      def configure(&)
        yield(Engine.config)
      end
    end
  end
end
