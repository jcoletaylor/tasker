# frozen_string_literal: true

# Example User model with Tasker authorization
# This can be used as a template for developers integrating with their user models
class UserWithTaskerAuth
  include Tasker::Concerns::Authorizable

  attr_accessor :id, :roles, :permissions

  def initialize(id:, roles: [], permissions: [])
    @id = id
    @roles = roles || []
    @permissions = permissions || []
  end

  # Configure the authorization methods
  configure_tasker_authorization(
    permission_method: :has_permission?,
    role_method: :user_roles,
    admin_method: :admin?
  )

  def has_permission?(permission)
    permissions.include?(permission)
  end

  def user_roles
    roles
  end

  def admin?
    user_roles.include?('admin')
  end

  # Example: resource-specific permission checking
  def tasker_permissions_for_resource(resource)
    case resource
    when 'tasker.task'
      if admin?
        %i[index show create update destroy retry cancel]
      else
        permissions.select { |p| p.start_with?('tasker.task:') }
                   .map { |p| p.split(':').last.to_sym }
      end
    when 'tasker.workflow_step'
      if admin?
        %i[index show update retry cancel]
      else
        %i[index show] # Regular users can only view steps
      end
    else
      []
    end
  end

  # Helper method for testing
  def add_permission(permission)
    @permissions << permission unless @permissions.include?(permission)
  end

  def add_role(role)
    @roles << role unless @roles.include?(role)
  end
end
