# typed: false
# frozen_string_literal: true

module Tasker
  module GraphQLTypes
  end
end

# Base classes first
require_relative 'graph_ql_types/base_argument'
require_relative 'graph_ql_types/base_field'
require_relative 'graph_ql_types/base_object'
require_relative 'graph_ql_types/base_scalar'
require_relative 'graph_ql_types/base_enum'
require_relative 'graph_ql_types/base_edge'
require_relative 'graph_ql_types/base_connection'
require_relative 'graph_ql_types/base_input_object'
require_relative 'graph_ql_types/base_interface'
require_relative 'graph_ql_types/base_union'

# Node interface
require_relative 'graph_ql_types/node_type'

# Basic types without dependencies
require_relative 'graph_ql_types/annotation_type'
require_relative 'graph_ql_types/dependent_system_type'
require_relative 'graph_ql_types/named_task_type'
require_relative 'graph_ql_types/named_step_type'

# Interfaces
require_relative 'graph_ql_types/task_interface'

# Types with dependencies
require_relative 'graph_ql_types/dependent_system_object_map_type'  # depends on dependent_system_type
require_relative 'graph_ql_types/named_tasks_named_step_type'       # depends on named_task_type and named_step_type
require_relative 'graph_ql_types/task_annotation_type' # depends on annotation_type
require_relative 'graph_ql_types/workflow_step_type' # depends on task_interface
require_relative 'graph_ql_types/task_type' # depends on task_interface

# Root types last
require_relative 'graph_ql_types/query_type'
require_relative 'graph_ql_types/mutation_type'
