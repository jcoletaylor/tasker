# typed: false
# frozen_string_literal: true

require 'json-schema'
require 'concurrent'
require_relative 'task_handler/class_methods'
require_relative 'task_handler/instance_methods'
require_relative 'task_handler/step_group'
require_relative 'task_builder'

module Tasker
  # Main module for task handler functionality
  #
  # TaskHandler provides the core functionality for defining and executing
  # workflows. When included in a class, it adds methods for:
  #
  # - Defining step templates with dependencies and configurations
  # - Initializing and running tasks with proper error handling
  # - Processing steps in sequence or concurrently
  # - Managing retries and error recovery
  #
  # @example Creating a basic task handler
  #   class MyTaskHandler
  #     include Tasker::TaskHandler
  #
  #     define_step_templates do |definer|
  #       definer.define(
  #         name: 'first_step',
  #         handler_class: SomeStepHandler
  #       )
  #     end
  #   end
  module TaskHandler
    # When included, extends the class with ClassMethods and includes InstanceMethods
    #
    # @param base [Class] The class including this module
    # @return [void]
    def self.included(base)
      base.extend(ClassMethods)
      base.include(InstanceMethods)
    end
  end
end
