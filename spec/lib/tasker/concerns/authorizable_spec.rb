# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Concerns::Authorizable do
  # Create a test class to include the concern
  let(:test_user_class) do
    Class.new do
      include Tasker::Concerns::Authorizable

      attr_accessor :id, :name, :roles, :permissions, :admin_flag

      def initialize(id:, name: nil, roles: [], permissions: [], admin: false)
        @id = id
        @name = name
        @roles = roles || []
        @permissions = permissions || []
        @admin_flag = admin
      end

      # Simulate different authorization patterns
      def admin?
        @admin_flag
      end

      def role
        @roles.first
      end
    end
  end

  let(:user) { test_user_class.new(id: 1, name: 'Test User') }
  let(:admin_user) { test_user_class.new(id: 2, name: 'Admin', admin: true) }
  let(:role_admin_user) { test_user_class.new(id: 3, name: 'Role Admin', roles: ['admin']) }

  describe 'class methods' do
    describe '.tasker_authorizable_config' do
      it 'returns default configuration' do
        config = test_user_class.tasker_authorizable_config

        expect(config).to be_a(Hash)
        expect(config[:permission_method]).to eq(:has_tasker_permission?)
        expect(config[:role_method]).to eq(:tasker_roles)
        expect(config[:admin_method]).to eq(:tasker_admin?)
      end

      it 'maintains separate configs for different classes' do
        other_class = Class.new { include Tasker::Concerns::Authorizable }

        test_user_class.configure_tasker_authorization(permission_method: :custom_method)

        expect(test_user_class.tasker_authorizable_config[:permission_method]).to eq(:custom_method)
        expect(other_class.tasker_authorizable_config[:permission_method]).to eq(:has_tasker_permission?)
      end
    end

    describe '.configure_tasker_authorization' do
      it 'allows customizing configuration options' do
        test_user_class.configure_tasker_authorization(
          permission_method: :can_do?,
          role_method: :user_roles,
          admin_method: :is_admin?
        )

        config = test_user_class.tasker_authorizable_config
        expect(config[:permission_method]).to eq(:can_do?)
        expect(config[:role_method]).to eq(:user_roles)
        expect(config[:admin_method]).to eq(:is_admin?)
      end

      it 'merges new options with existing config' do
        test_user_class.configure_tasker_authorization(permission_method: :custom_permission)

        config = test_user_class.tasker_authorizable_config
        expect(config[:permission_method]).to eq(:custom_permission)
        expect(config[:role_method]).to eq(:tasker_roles) # unchanged
        expect(config[:admin_method]).to eq(:tasker_admin?) # unchanged
      end
    end
  end

  describe 'instance methods' do
    describe '#has_tasker_permission?' do
      context 'with default implementation' do
        it 'returns false when no permissions method exists' do
          expect(user.has_tasker_permission?('tasker.task:show')).to be(false)
        end

        it 'uses permissions method when available' do
          user_with_permissions = test_user_class.new(
            id: 1,
            permissions: ['tasker.task:show', 'tasker.task:index']
          )

          # Add permissions method to the class
          test_user_class.define_method(:permissions) { @permissions }

          expect(user_with_permissions.has_tasker_permission?('tasker.task:show')).to be(true)
          expect(user_with_permissions.has_tasker_permission?('tasker.task:create')).to be(false)
        end
      end

      context 'with custom implementation' do
        before do
          test_user_class.define_method(:has_tasker_permission?) do |permission|
            permission == 'allowed.permission'
          end
        end

        it 'uses the custom implementation' do
          expect(user.has_tasker_permission?('allowed.permission')).to be(true)
          expect(user.has_tasker_permission?('denied.permission')).to be(false)
        end
      end
    end

    describe '#tasker_roles' do
      it 'returns empty array when no roles method exists' do
        expect(user.tasker_roles).to eq([])
      end

      it 'uses roles method when available' do
        user_with_roles = test_user_class.new(id: 1, roles: %w[editor viewer])

        # Add roles method to the class
        test_user_class.define_method(:roles) { @roles }

        expect(user_with_roles.tasker_roles).to eq(%w[editor viewer])
      end
    end

    describe '#tasker_admin?' do
      it 'checks admin? method when available' do
        expect(admin_user.tasker_admin?).to be(true)
        expect(user.tasker_admin?).to be(false)
      end

      it 'checks role method for admin role' do
        user_with_admin_role = test_user_class.new(id: 1, roles: ['admin'])
        expect(user_with_admin_role.tasker_admin?).to be(true)
      end

      it 'checks tasker_roles for admin role' do
        expect(role_admin_user.tasker_admin?).to be(true)
      end

      it 'returns false when no admin indicators present' do
        regular_user = test_user_class.new(id: 1, roles: ['user'], admin: false)
        expect(regular_user.tasker_admin?).to be(false)
      end
    end

    describe '#tasker_permissions_for_resource' do
      before do
        test_user_class.define_method(:has_tasker_permission?) do |permission|
          @permissions.include?(permission)
        end
      end

      it 'returns permitted actions for a resource' do
        user_with_permissions = test_user_class.new(
          id: 1,
          permissions: ['tasker.task:show', 'tasker.task:index', 'tasker.workflow_step:show']
        )

        task_permissions = user_with_permissions.tasker_permissions_for_resource('tasker.task')
        expect(task_permissions).to contain_exactly(:show, :index)

        step_permissions = user_with_permissions.tasker_permissions_for_resource('tasker.workflow_step')
        expect(step_permissions).to contain_exactly(:show)
      end

      it 'returns empty array for non-existent resource' do
        permissions = user.tasker_permissions_for_resource('invalid.resource')
        expect(permissions).to eq([])
      end

      it 'returns empty array when user has no permissions' do
        permissions = user.tasker_permissions_for_resource('tasker.task')
        expect(permissions).to eq([])
      end
    end

    describe '#can_access_tasker_resource?' do
      before do
        test_user_class.define_method(:has_tasker_permission?) do |permission|
          @permissions.include?(permission)
        end
      end

      it 'returns true when user has any permissions for the resource' do
        user_with_permissions = test_user_class.new(
          id: 1,
          permissions: ['tasker.task:show']
        )

        expect(user_with_permissions.can_access_tasker_resource?('tasker.task')).to be(true)
        expect(user_with_permissions.can_access_tasker_resource?('tasker.workflow_step')).to be(false)
      end

      it 'returns false when user has no permissions for the resource' do
        expect(user.can_access_tasker_resource?('tasker.task')).to be(false)
      end
    end

    describe '#all_tasker_permissions' do
      before do
        test_user_class.define_method(:has_tasker_permission?) do |permission|
          @permissions.include?(permission)
        end
      end

      it 'returns all Tasker permissions the user has' do
        user_with_permissions = test_user_class.new(
          id: 1,
          permissions: [
            'tasker.task:show',
            'tasker.task:index',
            'tasker.workflow_step:show',
            'non.tasker:permission' # Should be filtered out
          ]
        )

        all_permissions = user_with_permissions.all_tasker_permissions
        expect(all_permissions).to contain_exactly(
          'tasker.task:show',
          'tasker.task:index',
          'tasker.workflow_step:show'
        )
      end

      it 'returns empty array when user has no Tasker permissions' do
        user_with_no_tasker_perms = test_user_class.new(
          id: 1,
          permissions: ['other.app:permission']
        )

        expect(user_with_no_tasker_perms.all_tasker_permissions).to eq([])
      end
    end
  end

  describe 'integration with custom user models' do
    let(:custom_user_class) do
      Class.new do
        include Tasker::Concerns::Authorizable

        configure_tasker_authorization(
          permission_method: :can_perform?,
          role_method: :user_roles,
          admin_method: :is_admin?
        )

        attr_accessor :id, :permissions, :roles, :admin_status

        def initialize(id:, permissions: [], roles: [], admin: false)
          @id = id
          @permissions = permissions
          @roles = roles
          @admin_status = admin
        end

        def can_perform?(action)
          @permissions.include?(action)
        end

        def user_roles
          @roles
        end

        def is_admin?
          @admin_status
        end
      end
    end

    it 'uses custom method names correctly' do
      user = custom_user_class.new(
        id: 1,
        permissions: ['tasker.task:show'],
        roles: ['editor'],
        admin: true
      )

      expect(user.has_tasker_permission?('tasker.task:show')).to be(true)
      expect(user.has_tasker_permission?('tasker.task:create')).to be(false)
      expect(user.tasker_roles).to eq(['editor'])
      expect(user.tasker_admin?).to be(true)
    end
  end

  describe 'edge cases' do
    it 'handles users without any authorization methods' do
      minimal_user_class = Class.new { include Tasker::Concerns::Authorizable }
      user = minimal_user_class.new

      expect(user.has_tasker_permission?('any.permission')).to be(false)
      expect(user.tasker_roles).to eq([])
      expect(user.tasker_admin?).to be(false)
      expect(user.tasker_permissions_for_resource('tasker.task')).to eq([])
      expect(user.can_access_tasker_resource?('tasker.task')).to be(false)
      expect(user.all_tasker_permissions).to eq([])
    end

    it 'handles nil responses from authorization methods' do
      test_user_class.define_method(:permissions) { nil }
      test_user_class.define_method(:roles) { nil }

      expect(user.has_tasker_permission?('any.permission')).to be(false)
      expect(user.tasker_roles).to eq([])
    end
  end
end
