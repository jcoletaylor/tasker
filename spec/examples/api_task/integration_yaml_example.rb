# frozen_string_literal: true

require_relative 'step_handler'
module ApiTask
  class IntegrationYamlExample < Tasker::ConfiguredTaskBase
    def self.yaml_path
      Rails.root.join('../examples/api_task/config/integration_example.yaml')
    end
  end
end
