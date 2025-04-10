# frozen_string_literal: true

require 'tasker/engine'
# typed: strict

require 'tasker/constants'
require 'tasker/version'
require 'tasker/configuration'
require 'tasker/railtie' if defined?(Rails)

require 'tasker/types/types'
require 'tasker/types/step_template'
require 'tasker/types/step_sequence'
require 'tasker/types/task_request'

require 'tasker/identity_strategy'
require 'tasker/handler_factory'
require 'tasker/task_handler'
require 'tasker/task_handler/class_methods'
require 'tasker/task_handler/instance_methods'
require 'tasker/task_handler/step_group'

module Tasker
  module GraphQLTypes
  end

  module Types
  end

  # Delegate to Configuration class for easier access
  def self.configuration
    Configuration.configuration
  end

  # Reset configuration (for testing purposes)
  def self.reset_configuration!
    Configuration.reset_configuration!
  end
end
