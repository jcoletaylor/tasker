# frozen_string_literal: true

# typed: strict
module Tasker
  class Engine < ::Rails::Engine
    isolate_namespace Tasker
    config.generators.api_only = true
    config.generators.test_framework = :rspec
  end
end
