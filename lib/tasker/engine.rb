# frozen_string_literal: true

# typed: true

require 'rails'
require 'pg'
require 'sidekiq'
require 'sorbet-runtime'
require 'active_model_serializers'
require 'json-schema'
require 'graphql'
# require 'rswag-api'
# require 'rswag-ui'

module Tasker
  class Engine < ::Rails::Engine
    isolate_namespace Tasker
    config.generators.api_only = true
    config.generators.test_framework = :rspec
    config.application_controller = 'ActionController::API'

    class << self
      def configure
        yield Engine.config
      end
    end
  end
end
