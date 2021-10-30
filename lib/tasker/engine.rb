# frozen_string_literal: true

# typed: strict

require 'rails'
require 'pg'
require 'sidekiq'
require 'sorbet-runtime'
require 'active_model_serializers'
require 'json-schema'
require 'graphql'

module Tasker
  class Engine < ::Rails::Engine
    isolate_namespace Tasker
    config.generators.api_only = true
    config.generators.test_framework = :rspec
  end
end
