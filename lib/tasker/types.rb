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
  # pattern with proper documentation.
  module Types
  end
end

# Include all type definitions
require 'tasker/types/step_template'
require 'tasker/types/step_sequence'
require 'tasker/types/task_request'
