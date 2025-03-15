# typed: false
# frozen_string_literal: true

require 'json-schema'
require 'tasker/task_handler/instance_methods'
module Tasker
  module TaskHandler
    def self.included(klass)
      klass.extend(ClassMethods)
      klass.include(InstanceMethods)
    end
  end
end
