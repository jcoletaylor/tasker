# frozen_string_literal: true
# typed: false

require 'dry-types'
require 'dry-struct'

module Tasker
  # Types module for Tasker
  #
  # This module contains all the type definitions used by the Tasker gem.
  # It provides a central location for all type declarations, ensuring
  # consistent type usage across the application.
  #
  # Types are implemented using dry-struct and follow a consistent
  # pattern with proper documentation. The module includes basic types
  # for all Tasker data structures including:
  #
  # - StepTemplate - Defines the structure for workflow step templates
  # - StepSequence - Contains a sequence of workflow steps
  # - TaskRequest - Represents a request to create and execute a task
  #
  # @example Using a Tasker type
  #   task_request = Tasker::Types::TaskRequest.new(
  #     name: 'my_task',
  #     context: { id: 123 }
  #   )
  module Types
    # @!visibility private
    include Dry::Types()

    # Base configuration class that ensures immutability
    #
    # All Tasker configuration classes inherit from this base class
    # to ensure they are frozen after creation, providing immutability
    # and thread safety.
    #
    # Also automatically handles deep symbolization of nested hash attributes.
    class BaseConfig < Dry::Struct
      def initialize(*)
        super
        freeze
      end
    end
  end
end

# Include all type definitions
require 'tasker/types/step_template'
require 'tasker/types/step_sequence'
require 'tasker/types/task_request'

# Configuration types
require 'tasker/types/health_config'
require 'tasker/types/auth_config'
require 'tasker/types/database_config'
require 'tasker/types/telemetry_config'
require 'tasker/types/engine_config'
require 'tasker/types/dependency_graph_config'
require 'tasker/types/backoff_config'
require 'tasker/types/execution_config'

# Dependency graph types
require 'tasker/types/dependency_graph'
