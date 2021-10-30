module Tasker
  class Engine < ::Rails::Engine
    isolate_namespace Tasker
    config.generators.api_only = true
  end
end
