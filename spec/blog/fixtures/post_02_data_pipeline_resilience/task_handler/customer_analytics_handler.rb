# frozen_string_literal: true

module BlogExamples
  module Post02
    # CustomerAnalyticsHandler demonstrates YAML-driven task configuration
    # This example shows the ConfiguredTask pattern using manual YAML loading
    # for compatibility with the blog test framework
    class CustomerAnalyticsHandler < Tasker::ConfiguredTask
      def self.yaml_path
        @yaml_path ||= File.join(
          File.dirname(__FILE__),
          '..', 'config', 'customer_analytics_handler.yaml'
        )
      end
    end
  end
end
