# frozen_string_literal: true

require_relative 'smart_view_router'

module Tasker
  module Views
    # Backward Compatibility Layer for Scalable Database Views
    #
    # This module provides backward compatibility for existing TaskExecutionContext
    # and StepReadinessStatus usage while routing to the appropriate scalable views.
    #
    # It maintains the existing API contracts while providing performance improvements
    # through intelligent view routing.
    #
    module BackwardCompatibilityLayer
      extend ActiveSupport::Concern

      # Extend TaskExecutionContext with smart routing
      module TaskExecutionContextExtensions
        extend ActiveSupport::Concern

        class_methods do
          # Override find to use active scope by default (fastest for operational queries)
          def find(task_id)
            SmartViewRouter.get_task_execution_context(
              task_id: task_id,
              scope: :active
            )
          end

          # Override all to use active scope by default
          def all
            SmartViewRouter.get_task_execution_context(scope: :active)
          end

          # Override where to use active scope by default
          def where(conditions = {})
            if conditions[:task_id]
              SmartViewRouter.get_task_execution_context(
                task_id: conditions[:task_id],
                scope: :active
              )
            else
              SmartViewRouter.get_task_execution_context(scope: :active)
            end
          end

          # Provide explicit scope methods for different use cases
          def active(task_id: nil, limit: nil)
            SmartViewRouter.get_task_execution_context(
              task_id: task_id,
              scope: :active,
              limit: limit
            )
          end

          def recent(task_id: nil, limit: nil)
            SmartViewRouter.get_task_execution_context(
              task_id: task_id,
              scope: :recent,
              limit: limit
            )
          end

          def complete(task_id: nil, limit: nil)
            SmartViewRouter.get_task_execution_context(
              task_id: task_id,
              scope: :complete,
              limit: limit
            )
          end

          def single(task_id)
            SmartViewRouter.get_task_execution_context(
              task_id: task_id,
              scope: :single
            )
          end

          # Performance-aware batch methods
          def find_each(batch_size: 1000, scope: :active)
            offset = 0
            loop do
              batch = SmartViewRouter.get_task_execution_context(
                scope: scope,
                limit: batch_size
              )
              break if batch.empty?

              batch.each { |record| yield(record) }
              offset += batch_size
            end
          end

          def in_batches(batch_size: 1000, scope: :active)
            offset = 0
            loop do
              batch = SmartViewRouter.get_task_execution_context(
                scope: scope,
                limit: batch_size
              )
              break if batch.empty?

              yield(batch)
              offset += batch_size
            end
          end
        end
      end

      # Extend StepReadinessStatus with smart routing
      module StepReadinessStatusExtensions
        extend ActiveSupport::Concern

        class_methods do
          # Override find to use active scope by default
          def find(workflow_step_id)
            SmartViewRouter.get_step_readiness(
              workflow_step_id: workflow_step_id,
              scope: :active
            )
          end

          # Override all to use active scope by default
          def all
            SmartViewRouter.get_step_readiness(scope: :active)
          end

          # Override where to use active scope by default
          def where(conditions = {})
            SmartViewRouter.get_step_readiness(
              workflow_step_id: conditions[:workflow_step_id],
              task_id: conditions[:task_id],
              scope: :active
            )
          end

          # Provide explicit scope methods
          def active(workflow_step_id: nil, task_id: nil, limit: nil)
            SmartViewRouter.get_step_readiness(
              workflow_step_id: workflow_step_id,
              task_id: task_id,
              scope: :active,
              limit: limit
            )
          end

          def recent(workflow_step_id: nil, task_id: nil, limit: nil)
            SmartViewRouter.get_step_readiness(
              workflow_step_id: workflow_step_id,
              task_id: task_id,
              scope: :recent,
              limit: limit
            )
          end

          def complete(workflow_step_id: nil, task_id: nil, limit: nil)
            SmartViewRouter.get_step_readiness(
              workflow_step_id: workflow_step_id,
              task_id: task_id,
              scope: :complete,
              limit: limit
            )
          end

          # Performance-aware batch methods
          def find_each(batch_size: 1000, scope: :active)
            offset = 0
            loop do
              batch = SmartViewRouter.get_step_readiness(
                scope: scope,
                limit: batch_size
              )
              break if batch.empty?

              batch.each { |record| yield(record) }
              offset += batch_size
            end
          end
        end
      end

      # Configuration and monitoring methods
      module ConfigurationMethods
        extend ActiveSupport::Concern

        class_methods do
          # Get current default scope configuration
          def default_scope
            :active
          end

          # Set default scope for queries (thread-safe)
          def with_scope(scope)
            original_scope = Thread.current[:tasker_view_scope]
            Thread.current[:tasker_view_scope] = scope
            yield
          ensure
            Thread.current[:tasker_view_scope] = original_scope
          end

          # Get performance information for different scopes
          def scope_performance_info
            SmartViewRouter.available_scopes
          end

          # Get current scope (respects thread-local override)
          def current_scope
            Thread.current[:tasker_view_scope] || default_scope
          end
        end
      end

      # Monitoring and metrics methods
      module MonitoringMethods
        extend ActiveSupport::Concern

        class_methods do
          # Get query performance metrics
          def query_metrics(scope: :active, duration: 1.hour)
            {
              scope: scope,
              duration: duration,
              estimated_performance: SmartViewRouter.get_scope_info(scope)[:performance_target],
              description: SmartViewRouter.get_scope_info(scope)[:description]
            }
          end

          # Health check for view performance
          def health_check
            results = {}

            SmartViewRouter.available_scopes.each do |scope, config|
              start_time = Time.current

              begin
                # Test query for each scope
                case scope
                when :single
                  # Skip single scope for health check (requires task_id)
                  results[scope] = { status: :skipped, reason: 'requires_task_id' }
                else
                  SmartViewRouter.get_task_execution_context(scope: scope, limit: 1)
                  execution_time = Time.current - start_time

                  results[scope] = {
                    status: :healthy,
                    execution_time: execution_time.round(4),
                    target: config[:performance_target],
                    description: config[:description]
                  }
                end
              rescue => e
                results[scope] = {
                  status: :error,
                  error: e.message,
                  target: config[:performance_target]
                }
              end
            end

            results
          end
        end
      end
    end
  end
end

# Apply extensions to existing models if they exist
if defined?(Tasker::TaskExecutionContext)
  Tasker::TaskExecutionContext.include(Tasker::Views::BackwardCompatibilityLayer::TaskExecutionContextExtensions)
  Tasker::TaskExecutionContext.include(Tasker::Views::BackwardCompatibilityLayer::ConfigurationMethods)
  Tasker::TaskExecutionContext.include(Tasker::Views::BackwardCompatibilityLayer::MonitoringMethods)
end

if defined?(Tasker::StepReadinessStatus)
  Tasker::StepReadinessStatus.include(Tasker::Views::BackwardCompatibilityLayer::StepReadinessStatusExtensions)
  Tasker::StepReadinessStatus.include(Tasker::Views::BackwardCompatibilityLayer::ConfigurationMethods)
  Tasker::StepReadinessStatus.include(Tasker::Views::BackwardCompatibilityLayer::MonitoringMethods)
end
