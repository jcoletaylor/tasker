# frozen_string_literal: true

# Tasker: Queuable Multi-Step Tasks Made Easy-ish
#
# This is the main entry point for the Tasker gem. It sets up only the essential
# dependencies needed for the gem to function, while letting the Rails engine
# handle Rails-specific setup and autoloading.

# Load version first (required for gemspec and other components)
require 'tasker/version'

# Core configuration and errors that must be available before engine loads
require 'tasker/configuration'
require 'tasker/errors'

# Essential runtime dependencies from gemspec
require 'concurrent'
require 'dry/events'
require 'dry/types'
require 'dry/struct'
require 'dry/validation'
require 'statesman'

# Load the Rails engine to handle Rails-specific setup
require 'tasker/engine'

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

  # Namespace for event system components used in Tasker
  module Events
  end

  # Namespace for orchestration components
  module Orchestration
  end

  # Namespace for state machine components
  module StateMachine
  end

  # Accesses the global configuration for Tasker
  #
  # @yield [Configuration] The configuration instance if a block is given
  # @return [Tasker::Configuration] The current configuration
  def self.configuration(&)
    Configuration.configuration(&)
  end

  # Configure Tasker with a block
  #
  # @yield [Configuration] The configuration instance for setting options
  # @return [Tasker::Configuration] The current configuration
  def self.configure
    yield(configuration) if block_given?
    configuration
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
