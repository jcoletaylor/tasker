# frozen_string_literal: true

require_relative 'step_handler'
module ApiTask
  class IntegrationYamlExample < Tasker::ConfiguredTask
    def self.task_name
      'integration_example'
    end
  end
end
