# typed: false
# frozen_string_literal: true

module Tasker
  module GraphQLTypes
    class WorkflowStepType < GraphQLTypes::BaseObject
      field :workflow_step_id, ID, null: false
      field :task_id, Integer, null: false
      field :named_step_id, Integer, null: false
      field :status, String, null: false
      field :retryable, Boolean, null: false
      field :retry_limit, Integer, null: true
      field :in_process, Boolean, null: false
      field :processed, Boolean, null: false
      field :processed_at, GraphQL::Types::ISO8601DateTime, null: true
      field :attempts, Integer, null: true
      field :last_attempted_at, GraphQL::Types::ISO8601DateTime, null: true
      field :backoff_request_seconds, Integer, null: true
      field :inputs, GraphQL::Types::JSON, null: true
      field :results, GraphQL::Types::JSON, null: true
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
      field :skippable, Boolean, null: false
      field :task, GraphQLTypes::TaskInterface, null: true
      field :named_step, [GraphQLTypes::NamedStepType], null: true

      # Optimized parent/child fields using scenic view to eliminate N+1 queries
      field :children, [GraphQLTypes::WorkflowStepType], null: true do
        description "Child steps in the workflow DAG"
      end

      field :parents, [GraphQLTypes::WorkflowStepType], null: true do
        description "Parent steps in the workflow DAG"
      end

      # New efficient fields for IDs only (when full objects aren't needed)
      field :parent_step_ids, [ID], null: false do
        description "IDs of parent steps (efficient lookup via scenic view)"
      end

      field :child_step_ids, [ID], null: false do
        description "IDs of child steps (efficient lookup via scenic view)"
      end

      # DAG position information from scenic view
      field :is_root_step, Boolean, null: false do
        description "Whether this step has no dependencies"
      end

      field :is_leaf_step, Boolean, null: false do
        description "Whether this step has no downstream dependencies"
      end

      field :parent_count, Integer, null: false do
        description "Number of parent dependencies"
      end

      field :child_count, Integer, null: false do
        description "Number of child dependencies"
      end

      # Resolver methods using scenic view optimization
      def parent_step_ids
        # Handle both WorkflowStep objects and Hash objects from mutations
        if object.is_a?(Hash)
          object[:parents_ids] || []
        else
          object.step_dag_relationship&.parent_step_ids_array || []
        end
      end

      def child_step_ids
        # Handle both WorkflowStep objects and Hash objects from mutations
        if object.is_a?(Hash)
          object[:children_ids] || []
        else
          object.step_dag_relationship&.child_step_ids_array || []
        end
      end

      def is_root_step
        # Handle both WorkflowStep objects and Hash objects from mutations
        if object.is_a?(Hash)
          parent_step_ids.empty?
        else
          object.step_dag_relationship&.is_root_step || false
        end
      end

      def is_leaf_step
        # Handle both WorkflowStep objects and Hash objects from mutations
        if object.is_a?(Hash)
          child_step_ids.empty?
        else
          object.step_dag_relationship&.is_leaf_step || false
        end
      end

      def parent_count
        # Handle both WorkflowStep objects and Hash objects from mutations
        if object.is_a?(Hash)
          parent_step_ids.length
        else
          object.step_dag_relationship&.parent_count || 0
        end
      end

      def child_count
        # Handle both WorkflowStep objects and Hash objects from mutations
        if object.is_a?(Hash)
          child_step_ids.length
        else
          object.step_dag_relationship&.child_count || 0
        end
      end

      def parents
        # Handle both WorkflowStep objects and Hash objects from mutations
        parent_ids = parent_step_ids
        return [] if parent_ids.empty?

        # For Hash objects from mutations, we need to fetch the actual WorkflowStep objects
        if object.is_a?(Hash)
          # Use task_id from the hash to scope the query
          task_id = object[:task_id]
          return [] unless task_id

          WorkflowStep.where(task_id: task_id, workflow_step_id: parent_ids)
        else
          # Batch load all parent steps at once
          WorkflowStep.where(workflow_step_id: parent_ids)
        end
      end

      def children
        # Handle both WorkflowStep objects and Hash objects from mutations
        child_ids = child_step_ids
        return [] if child_ids.empty?

        # For Hash objects from mutations, we need to fetch the actual WorkflowStep objects
        if object.is_a?(Hash)
          # Use task_id from the hash to scope the query
          task_id = object[:task_id]
          return [] unless task_id

          WorkflowStep.where(task_id: task_id, workflow_step_id: child_ids)
        else
          # Batch load all child steps at once
          WorkflowStep.where(workflow_step_id: child_ids)
        end
      end
    end
  end
end
