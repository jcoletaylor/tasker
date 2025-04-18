# frozen_string_literal: true

require 'tasker/engine'
# typed: false

require 'tasker/constants'
require 'tasker/version'
require 'tasker/configuration'
require 'tasker/railtie' if defined?(Rails)

require 'tasker/types'
require 'tasker/types/step_template'
require 'tasker/types/step_sequence'
require 'tasker/types/task_request'

require 'tasker/identity_strategy'
require 'tasker/handler_factory'
require 'tasker/task_handler'
require 'tasker/task_handler/class_methods'
require 'tasker/task_handler/instance_methods'
require 'tasker/task_handler/step_group'

# Main namespace for the Tasker gem
#
# Tasker is a Rails engine that provides a flexible and powerful
# task processing system for building complex workflows with
# retries, error handling, and concurrency.
module Tasker
  # Namespace for GraphQL types used in the Tasker API
  module GraphQLTypes
  end

  # Namespace for data structure types used in Tasker
  module Types
  end

  # Accesses the global configuration for Tasker
  #
  # @return [Tasker::Configuration] The current configuration
  def self.configuration
    Configuration.configuration
  end

  # Resets the configuration to default values
  #
  # Primarily used for testing to ensure a clean configuration state.
  #
  # @return [Tasker::Configuration] A new configuration instance
  def self.reset_configuration!
    Configuration.reset_configuration!
  end
end
