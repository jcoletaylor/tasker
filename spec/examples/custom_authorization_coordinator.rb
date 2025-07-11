# frozen_string_literal: true

require_relative '../../lib/tasker/authorization'

# Example authorization coordinator implementation for comprehensive authorization scenarios.
#
# This coordinator demonstrates:
# - Resource-based authorization using constants
# - Role-based access control (admin vs regular users)
# - Permission-based access control (explicit permissions)
# - Custom business logic (task ownership)
# - Integration with user models through the Authorizable concern
#
# Usage:
#   Tasker::Configuration.configuration do |config|
#     config.auth do |auth|
#       auth.strategy = :custom
#       auth.options = { authenticator_class: 'YourAuthenticator' }
#       auth.enabled = true
#       auth.coordinator_class = 'CustomAuthorizationCoordinator'
#     end
#   end
#
# User Model Integration:
#   Your user model should include Tasker::Concerns::Authorizable and implement:
#   - has_tasker_permission?(permission) - Check specific permissions
#   - tasker_admin? - Check if user is an admin
#   - tasker_roles - Return array of user roles
class CustomAuthorizationCoordinator < Tasker::Authorization::BaseCoordinator
  include Tasker::Authorization::ResourceConstants

  protected

  # Main authorization method - determines if user can perform action on resource
  #
  # @param resource [String] Resource name (e.g., 'tasker.task')
  # @param action [Symbol] Action to perform (e.g., :show, :create)
  # @param context [Hash] Additional context (controller, params, etc.)
  # @return [Boolean] True if authorized
  def authorized?(resource, action, context = {})
    case resource
    when RESOURCES::TASK
      authorize_task_action(action, context)
    when RESOURCES::WORKFLOW_STEP
      authorize_step_action(action, context)
    when RESOURCES::HEALTH_STATUS
      authorize_health_status_action(action, context)
    when RESOURCES::METRICS
      authorize_metrics_action(action, context)
    else
      false
    end
  end

  private

  # Authorization logic for task operations
  #
  # Implements the following rules:
  # - Anyone with appropriate permissions can read tasks
  # - Admin users or users with explicit permissions can create/modify tasks
  # - Task retry/cancel requires admin privileges or task ownership
  def authorize_task_action(action, context)
    return false unless user.respond_to?(:has_tasker_permission?)

    case action
    when :index, :show
      # Read operations: admin or explicit permissions
      user.tasker_admin? || user.has_tasker_permission?("#{RESOURCES::TASK}:#{action}")
    when :create, :update, :destroy
      # Write operations: admin or explicit permission required
      user.tasker_admin? || user.has_tasker_permission?("#{RESOURCES::TASK}:#{action}")
    when :retry, :cancel
      # Special operations: admin, explicit permission, or task ownership
      task_id = context[:resource_id]
      user.tasker_admin? ||
        user.has_tasker_permission?("#{RESOURCES::TASK}:#{action}") ||
        owns_task?(task_id)
    else
      false
    end
  end

  # Authorization logic for workflow step operations
  #
  # Implements the following rules:
  # - Anyone with appropriate permissions can read steps
  # - Only admin users can modify steps (steps are generally immutable)
  def authorize_step_action(action, _context)
    return false unless user.respond_to?(:has_tasker_permission?)

    case action
    when :index, :show
      # Read operations: admin or explicit permissions
      user.tasker_admin? || user.has_tasker_permission?("#{RESOURCES::WORKFLOW_STEP}:#{action}")
    when :update, :destroy, :retry, :cancel
      # Write operations: admin only (steps are critical workflow components)
      user.tasker_admin? || user.has_tasker_permission?("#{RESOURCES::WORKFLOW_STEP}:#{action}")
    else
      false
    end
  end

  # Authorization logic for health status operations
  #
  # Implements the following rules:
  # - Admin users can always access health status
  # - Regular users need explicit health_status.index permission
  # - Health status is read-only (no create/update/delete operations)
  def authorize_health_status_action(action, _context)
    return false unless user.respond_to?(:has_tasker_permission?)

    case action
    when :index
      # Health status reading: admin or explicit permission
      user.tasker_admin? || user.has_tasker_permission?("#{RESOURCES::HEALTH_STATUS}:#{action}")
    else
      false
    end
  end

  # Authorization logic for metrics operations
  #
  # Implements the following rules:
  # - Admin users can always access metrics
  # - Regular users need explicit metrics.index permission
  # - Metrics are read-only (no create/update/delete operations)
  def authorize_metrics_action(action, _context)
    return false unless user.respond_to?(:has_tasker_permission?)

    case action
    when :index
      # Metrics reading: admin or explicit permission
      user.tasker_admin? || user.has_tasker_permission?("#{RESOURCES::METRICS}:#{action}")
    else
      false
    end
  end

  # Custom business logic: check if user owns a task
  #
  # This demonstrates how to implement custom authorization rules
  # based on data ownership or other business logic.
  #
  # @param task_id [String] The task ID to check ownership for
  # @return [Boolean] True if user owns the task
  def owns_task?(task_id)
    return false unless task_id && user

    # Find the task
    task = Tasker::Task.find_by(task_id: task_id)
    return false unless task

    # Check ownership based on task context
    # This assumes the task context stores the creator's user ID
    task.context['created_by_user_id'] == user.id.to_s
  end

  # Additional helper method: check if user has any admin-like privileges
  #
  # This can be useful for debugging or complex authorization scenarios
  def privileged_user?
    return false unless user

    user.tasker_admin? ||
      user.tasker_roles.include?('admin') ||
      user.tasker_roles.include?('super_user')
  end

  # Additional helper method: check if user has read access to a resource
  #
  # This can be used for UI decisions (showing/hiding links, etc.)
  def can_read_resource?(resource)
    return false unless user

    case resource
    when RESOURCES::TASK
      user.has_tasker_permission?("#{RESOURCES::TASK}:index") ||
        user.has_tasker_permission?("#{RESOURCES::TASK}:show")
    when RESOURCES::WORKFLOW_STEP
      user.has_tasker_permission?("#{RESOURCES::WORKFLOW_STEP}:index") ||
        user.has_tasker_permission?("#{RESOURCES::WORKFLOW_STEP}:show")
    else
      false
    end
  end
end
