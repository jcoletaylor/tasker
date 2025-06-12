# frozen_string_literal: true

module Tasker
  # ActiveRecord model backed by the active task execution context view
  # This provides fast operational queries for incomplete tasks only
  class ActiveTaskExecutionContext < ApplicationRecord
    self.table_name = 'tasker_active_task_execution_contexts'
    self.primary_key = 'task_id'

    # Associations
    belongs_to :task, class_name: 'Tasker::Task'

    # Scopes using view-calculated fields - no business logic duplication
    scope :ready_for_execution, -> { where('ready_steps > 0') }
    scope :processing, -> { where(execution_status: 'processing') }
    scope :blocked, -> { where(execution_status: 'blocked_by_failures') }
    scope :healthy, -> { where(health_status: 'healthy') }
    scope :with_failures, -> { where('failed_steps > 0') }
    scope :near_completion, ->(threshold = 90) { where(completion_percentage: threshold..) }

    # Use view-calculated fields for complex business logic
    scope :needs_attention, -> { where(recommended_action: %w[execute_ready_steps handle_failures]) }
    scope :by_health, ->(status) { where(health_status: status) }

    # Class methods for common operations
    class << self
      # Get context for a specific task
      def for_task(task_id)
        find_by(task_id: task_id)
      end

      # Performance monitoring - get slow tasks
      def slow_tasks(step_threshold = 10)
        where(total_steps: step_threshold..)
          .where('completion_percentage < 50')
      end
    end

    # Instance methods - delegate to view-calculated fields
    def ready_to_execute?
      ready_steps.positive?
    end

    def has_failures?
      failed_steps.positive?
    end

    def nearly_complete?(threshold = 90)
      completion_percentage >= threshold
    end

    def needs_attention?
      recommended_action.in?(%w[execute_ready_steps handle_failures])
    end

    # Summary methods using view-calculated data
    def progress_summary
      {
        total: total_steps,
        completed: completed_steps,
        pending: pending_steps,
        in_progress: in_progress_steps,
        failed: failed_steps,
        ready: ready_steps,
        percentage: completion_percentage,
        execution_status: execution_status,
        health_status: health_status,
        recommended_action: recommended_action
      }
    end

    # Read-only model - prevent modifications
    def readonly?
      true
    end
  end
end
