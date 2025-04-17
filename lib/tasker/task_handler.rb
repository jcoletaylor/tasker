# typed: false
# frozen_string_literal: true

require 'json-schema'
require 'concurrent'
require_relative 'task_handler/class_methods'
require_relative 'task_handler/instance_methods'
require_relative 'task_handler/step_group'
require_relative 'task_builder'

module Tasker
  module TaskHandler
    def self.included(base)
      base.extend(ClassMethods)
      base.include(InstanceMethods)
    end
  end
end
