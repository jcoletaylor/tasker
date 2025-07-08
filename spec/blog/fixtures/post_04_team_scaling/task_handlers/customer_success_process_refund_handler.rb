# frozen_string_literal: true

module CustomerSuccess
  class ProcessRefundHandler < Tasker::ConfiguredTask
    def self.yaml_path
      @yaml_path ||= File.join(
        File.dirname(__FILE__),
        '..', 'config', 'customer_success_process_refund.yaml'
      )
    end

    def self.namespace_name
      config&.dig('namespace_name') || 'customer_success'
    end

    def self.version
      config&.dig('version') || '1.3.0'
    end

    def self.description
      config&.dig('description') || 'Process customer service refunds with approval workflow'
    end
  end
end
