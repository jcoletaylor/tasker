# typed: false
# frozen_string_literal: true

module Tasker
  class HandlerFactory
    include Singleton
    attr_accessor :handler_classes

    def initialize
      self.handler_classes ||= {}
    end

    def get(name)
      raise(Tasker::ProceduralError, "No task handler for #{name}") unless handler_classes[name.to_sym]

      handler_classes[name.to_sym].to_s.camelize.constantize.new
    end

    def register(name, class_name)
      self.handler_classes[name.to_sym] = class_name.to_s
    end
  end
end
