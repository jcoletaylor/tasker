# frozen_string_literal: true

module Payments
  class ProcessRefundHandler < Tasker::ConfiguredTask
    def self.yaml_path
      @yaml_path ||= File.join(
        File.dirname(__FILE__),
        '..', 'config', 'payments_process_refund.yaml'
      )
    end

    def self.namespace_name
      config&.dig('namespace_name') || 'payments'
    end

    def self.version
      config&.dig('version') || '2.1.0'
    end

    def self.description
      config&.dig('description') || 'Process payment gateway refunds with direct API integration'
    end
  end
end
