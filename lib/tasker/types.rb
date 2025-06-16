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
  end
end

# Include all type definitions
require 'tasker/types/step_template'
require 'tasker/types/step_sequence'
require 'tasker/types/task_request'
