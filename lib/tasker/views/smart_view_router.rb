# frozen_string_literal: true

module Tasker
  module Views
    # Smart View Router for Scalable Database Views
    #
    # This service routes queries to the appropriate view based on scope and use case.
    # It provides different performance tiers for different operational needs:
    #
    # - :active - Fast queries for active workflow orchestration (<100ms)
    # - :recent - Monitoring and debugging queries (<500ms)
    # - :complete - Full historical analysis (<5s with pagination)
    # - :single - Individual task/step queries (<50ms)
    #
    # @example Basic usage
    #   # Get active task execution context (fastest)
    #   context = SmartViewRouter.get_task_execution_context(task_id: 123)
    #
    #   # Get recent history for monitoring
    #   contexts = SmartViewRouter.get_task_execution_context(scope: :recent)
    #
    #   # Get single task with full context
    #   context = SmartViewRouter.get_task_execution_context(task_id: 123, scope: :single)
    #
    class SmartViewRouter
      # Configuration for view scoping
      SCOPE_CONFIG = {
        active: {
          description: 'Active tasks and unprocessed steps only',
          performance_target: '100ms',
          task_model: 'Tasker::ActiveTaskExecutionContext',
          step_model: 'Tasker::ActiveStepReadinessStatus'
        },
        recent: {
          description: 'Tasks from last 30 days',
          performance_target: '500ms',
          task_model: 'Tasker::RecentTaskExecutionContext',
          step_model: 'Tasker::RecentStepReadinessStatus'
        },
        complete: {
          description: 'All historical tasks and steps',
          performance_target: '5s',
          task_model: 'Tasker::TaskExecutionContext',
          step_model: 'Tasker::StepReadinessStatus'
        },
        single: {
          description: 'Individual task/step with full context',
          performance_target: '50ms',
          task_model: 'Tasker::ActiveTaskExecutionContext',
          step_model: 'Tasker::ActiveStepReadinessStatus'
        }
      }.freeze

      class << self
        # Get task execution context with intelligent routing
        #
        # @param task_id [Integer, nil] Specific task ID to query
        # @param scope [Symbol] Query scope (:active, :recent, :complete, :single)
        # @param limit [Integer] Limit for batch queries (ignored for single task)
        # @return [Object, Array] Single context or array of contexts
        def get_task_execution_context(task_id: nil, scope: :active, limit: nil)
          validate_scope!(scope)

          case scope
          when :single
            get_single_task_execution_context(task_id)
          when :active
            get_active_task_execution_context(task_id, limit)
          when :recent
            get_recent_task_execution_context(task_id, limit)
          when :complete
            get_complete_task_execution_context(task_id, limit)
          end
        end

        # Get step readiness status with intelligent routing
        #
        # @param workflow_step_id [Integer, nil] Specific step ID to query
        # @param task_id [Integer, nil] Task ID to filter steps
        # @param scope [Symbol] Query scope (:active, :recent, :complete)
        # @param limit [Integer] Limit for batch queries
        # @return [Object, Array] Single status or array of statuses
        def get_step_readiness(workflow_step_id: nil, task_id: nil, scope: :active, limit: nil)
          validate_scope!(scope)
          raise ArgumentError, 'Single scope not supported for step readiness' if scope == :single

          model_class = get_step_model_class(scope)
          query = build_step_query(model_class, workflow_step_id, task_id, limit)

          if workflow_step_id
            query.first
          else
            query.to_a
          end
        end

        # Get performance metrics for different scopes
        #
        # @param scope [Symbol] Query scope to analyze
        # @return [Hash] Performance metrics and configuration
        def get_scope_info(scope)
          validate_scope!(scope)
          SCOPE_CONFIG[scope].dup
        end

        # Get all available scopes with their configurations
        #
        # @return [Hash] All scope configurations
        def available_scopes
          SCOPE_CONFIG.dup
        end

        private

        # Validate that the requested scope is supported
        def validate_scope!(scope)
          unless SCOPE_CONFIG.key?(scope)
            raise ArgumentError, "Unsupported scope: #{scope}. Available: #{SCOPE_CONFIG.keys.join(', ')}"
          end
        end

        # Get single task execution context using active view with WHERE clause
        def get_single_task_execution_context(task_id)
          raise ArgumentError, 'task_id is required for single scope' unless task_id

          # Use the active view with a simple WHERE clause - same performance as function
          result = ActiveRecord::Base.connection.execute(
            "SELECT * FROM tasker_active_task_execution_contexts WHERE task_id = #{task_id.to_i}"
          )

          return nil if result.count == 0

          # Convert result to hash with symbolized keys
          row = result.first
          {
            task_id: row['task_id']&.to_i,
            named_task_id: row['named_task_id']&.to_i,
            status: row['status'],
            total_steps: row['total_steps']&.to_i,
            pending_steps: row['pending_steps']&.to_i,
            in_progress_steps: row['in_progress_steps']&.to_i,
            completed_steps: row['completed_steps']&.to_i,
            failed_steps: row['failed_steps']&.to_i,
            ready_steps: row['ready_steps']&.to_i,
            execution_status: row['execution_status'],
            recommended_action: row['recommended_action'],
            completion_percentage: row['completion_percentage']&.to_f,
            health_status: row['health_status']
          }
        end

        # Get active task execution context (fastest operational queries)
        def get_active_task_execution_context(task_id, limit)
          # For now, use direct SQL until we create the ActiveRecord models
          query = "SELECT * FROM tasker_active_task_execution_contexts"
          query += " WHERE task_id = #{task_id.to_i}" if task_id
          query += " LIMIT #{limit.to_i}" if limit && !task_id

          result = ActiveRecord::Base.connection.execute(query)

          if task_id
            result.count > 0 ? convert_task_result(result.first) : nil
          else
            result.map { |row| convert_task_result(row) }
          end
        end

        # Get recent task execution context (monitoring queries)
        def get_recent_task_execution_context(task_id, limit)
          # Use the complete view with time filtering for now
          # TODO: Implement dedicated recent view
          get_complete_task_execution_context(task_id, limit)
        end

        # Get complete task execution context (full historical queries)
        def get_complete_task_execution_context(task_id, limit)
          query = "SELECT * FROM tasker_task_execution_contexts"
          query += " WHERE task_id = #{task_id.to_i}" if task_id
          query += " LIMIT #{limit.to_i}" if limit && !task_id

          result = ActiveRecord::Base.connection.execute(query)

          if task_id
            result.count > 0 ? convert_task_result(result.first) : nil
          else
            result.map { |row| convert_task_result(row) }
          end
        end

        # Get the appropriate step model class for the scope
        def get_step_model_class(scope)
          case scope
          when :active
            # For now, use direct SQL until we create the ActiveRecord models
            :active_sql
          when :recent
            :recent_sql
          when :complete
            :complete_sql
          end
        end

        # Build step query based on parameters
        def build_step_query(model_class, workflow_step_id, task_id, limit)
          case model_class
          when :active_sql
            query = "SELECT * FROM tasker_active_step_readiness_statuses"
          when :recent_sql
            # TODO: Implement recent step readiness view
            query = "SELECT * FROM tasker_step_readiness_statuses"
          when :complete_sql
            query = "SELECT * FROM tasker_step_readiness_statuses"
          end

          conditions = []
          conditions << "workflow_step_id = #{workflow_step_id.to_i}" if workflow_step_id
          conditions << "task_id = #{task_id.to_i}" if task_id

          query += " WHERE #{conditions.join(' AND ')}" if conditions.any?
          query += " LIMIT #{limit.to_i}" if limit

          # Return a simple query executor
          QueryExecutor.new(query)
        end

        # Convert database result row to hash
        def convert_task_result(row)
          {
            task_id: row['task_id']&.to_i,
            named_task_id: row['named_task_id']&.to_i,
            status: row['status'],
            total_steps: row['total_steps']&.to_i,
            pending_steps: row['pending_steps']&.to_i,
            in_progress_steps: row['in_progress_steps']&.to_i,
            completed_steps: row['completed_steps']&.to_i,
            failed_steps: row['failed_steps']&.to_i,
            ready_steps: row['ready_steps']&.to_i,
            execution_status: row['execution_status'],
            recommended_action: row['recommended_action'],
            completion_percentage: row['completion_percentage']&.to_f,
            health_status: row['health_status']
          }
        end
      end

      # Simple query executor for step queries
      class QueryExecutor
        def initialize(sql)
          @sql = sql
        end

        def first
          result = ActiveRecord::Base.connection.execute(@sql + " LIMIT 1")
          result.count > 0 ? convert_step_result(result.first) : nil
        end

        def to_a
          result = ActiveRecord::Base.connection.execute(@sql)
          result.map { |row| convert_step_result(row) }
        end

        private

        def convert_step_result(row)
          {
            workflow_step_id: row['workflow_step_id']&.to_i,
            task_id: row['task_id']&.to_i,
            named_step_id: row['named_step_id']&.to_i,
            name: row['name'],
            current_state: row['current_state'],
            dependencies_satisfied: row['dependencies_satisfied'],
            retry_eligible: row['retry_eligible'],
            ready_for_execution: row['ready_for_execution'],
            last_failure_at: row['last_failure_at'],
            next_retry_at: row['next_retry_at'],
            total_parents: row['total_parents']&.to_i,
            completed_parents: row['completed_parents']&.to_i,
            attempts: row['attempts']&.to_i,
            retry_limit: row['retry_limit']&.to_i,
            backoff_request_seconds: row['backoff_request_seconds']&.to_i,
            last_attempted_at: row['last_attempted_at']
          }
        end
      end
    end
  end
end
