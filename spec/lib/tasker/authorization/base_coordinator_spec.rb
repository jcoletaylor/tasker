# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Authorization::BaseCoordinator do
  let(:user) { double('User', id: 123, name: 'Test User') }
  let(:coordinator) { described_class.new(user) }
  let(:coordinator_without_user) { described_class.new }

  before do
    # Reset configuration before each test
    Tasker.configuration { |config| config.auth { |auth| auth.authorization_enabled = false } }
  end

  describe '#initialize' do
    it 'accepts a user parameter' do
      coordinator = described_class.new(user)
      expect(coordinator.send(:user)).to eq(user)
    end

    it 'works without a user parameter' do
      coordinator = described_class.new
      expect(coordinator.send(:user)).to be_nil
    end
  end

  describe '#authorize!' do
    context 'when authorization is disabled' do
      before { Tasker.configuration { |config| config.auth { |auth| auth.authorization_enabled = false } } }

      it 'returns true for any resource and action' do
        expect(coordinator.authorize!('tasker.task', :show)).to be(true)
        expect(coordinator.authorize!('tasker.workflow_step', :index)).to be(true)
      end

      it 'works without a user' do
        expect(coordinator_without_user.authorize!('tasker.task', :show)).to be(true)
      end
    end

    context 'when authorization is enabled' do
      before { Tasker.configuration { |config| config.auth { |auth| auth.authorization_enabled = true } } }

      it 'raises UnauthorizedError for default implementation' do
        expect do
          coordinator.authorize!('tasker.task', :show)
        end.to raise_error(Tasker::Authorization::UnauthorizedError, 'Not authorized to show on tasker.task')
      end

      it 'raises ArgumentError for invalid resource:action combinations' do
        expect do
          coordinator.authorize!('invalid.resource', :show)
        end.to raise_error(ArgumentError, "Unknown resource:action 'invalid.resource:show'")

        expect do
          coordinator.authorize!('tasker.task', :invalid_action)
        end.to raise_error(ArgumentError, "Unknown resource:action 'tasker.task:invalid_action'")
      end

      it 'validates against the resource registry' do
        # Valid combinations should not raise ArgumentError (but will raise UnauthorizedError due to default implementation)
        expect do
          coordinator.authorize!('tasker.task', :show)
        end.to raise_error(Tasker::Authorization::UnauthorizedError)

        expect do
          coordinator.authorize!('tasker.workflow_step', :index)
        end.to raise_error(Tasker::Authorization::UnauthorizedError)
      end

      it 'accepts string actions' do
        expect do
          coordinator.authorize!('tasker.task', 'show')
        end.to raise_error(Tasker::Authorization::UnauthorizedError)
      end

      it 'passes context to authorization check' do
        context = { task_id: 123, user_id: 456 }

        expect do
          coordinator.authorize!('tasker.task', :show, context)
        end.to raise_error(Tasker::Authorization::UnauthorizedError)
      end
    end
  end

  describe '#can?' do
    context 'when authorization is disabled' do
      before { Tasker.configuration { |config| config.auth { |auth| auth.authorization_enabled = false } } }

      it 'returns true for any resource and action' do
        expect(coordinator.can?('tasker.task', :show)).to be(true)
        expect(coordinator.can?('tasker.workflow_step', :index)).to be(true)
      end
    end

    context 'when authorization is enabled' do
      before { Tasker.configuration { |config| config.auth { |auth| auth.authorization_enabled = true } } }

      it 'returns false for default implementation' do
        expect(coordinator.can?('tasker.task', :show)).to be(false)
        expect(coordinator.can?('tasker.workflow_step', :index)).to be(false)
      end

      it 'raises ArgumentError for invalid resource:action combinations' do
        expect do
          coordinator.can?('invalid.resource', :show)
        end.to raise_error(ArgumentError, "Unknown resource:action 'invalid.resource:show'")

        expect do
          coordinator.can?('tasker.task', :invalid_action)
        end.to raise_error(ArgumentError, "Unknown resource:action 'tasker.task:invalid_action'")
      end

      it 'accepts context parameter' do
        context = { task_id: 123 }
        expect(coordinator.can?('tasker.task', :show, context)).to be(false)
      end
    end
  end

  describe 'subclass implementation' do
    let(:custom_coordinator_class) do
      Class.new(described_class) do
        protected

        def authorized?(resource, action, _context = {})
          return true if user&.name == 'Admin User'
          return true if resource == 'tasker.task' && action == :show && user&.name == 'Test User'

          false
        end
      end
    end

    let(:admin_user) { double('AdminUser', id: 1, name: 'Admin User') }
    let(:test_user) { double('TestUser', id: 2, name: 'Test User') }
    let(:regular_user) { double('RegularUser', id: 3, name: 'Regular User') }

    before { Tasker.configuration { |config| config.auth { |auth| auth.authorization_enabled = true } } }

    it 'allows custom authorization logic' do
      admin_coordinator = custom_coordinator_class.new(admin_user)
      test_coordinator = custom_coordinator_class.new(test_user)
      regular_coordinator = custom_coordinator_class.new(regular_user)

      # Admin can do everything
      expect(admin_coordinator.can?('tasker.task', :show)).to be(true)
      expect(admin_coordinator.can?('tasker.task', :create)).to be(true)
      expect(admin_coordinator.can?('tasker.workflow_step', :index)).to be(true)

      # Test user can only view tasks
      expect(test_coordinator.can?('tasker.task', :show)).to be(true)
      expect(test_coordinator.can?('tasker.task', :create)).to be(false)
      expect(test_coordinator.can?('tasker.workflow_step', :index)).to be(false)

      # Regular user can't do anything
      expect(regular_coordinator.can?('tasker.task', :show)).to be(false)
      expect(regular_coordinator.can?('tasker.task', :create)).to be(false)
      expect(regular_coordinator.can?('tasker.workflow_step', :index)).to be(false)
    end

    it 'works with authorize! method' do
      admin_coordinator = custom_coordinator_class.new(admin_user)
      test_coordinator = custom_coordinator_class.new(test_user)
      regular_coordinator = custom_coordinator_class.new(regular_user)

      # Admin can authorize
      expect(admin_coordinator.authorize!('tasker.task', :show)).to be(true)

      # Test user can authorize for specific action
      expect(test_coordinator.authorize!('tasker.task', :show)).to be(true)

      # Test user cannot authorize for other actions
      expect do
        test_coordinator.authorize!('tasker.task', :create)
      end.to raise_error(Tasker::Authorization::UnauthorizedError)

      # Regular user cannot authorize
      expect do
        regular_coordinator.authorize!('tasker.task', :show)
      end.to raise_error(Tasker::Authorization::UnauthorizedError)
    end

    it 'receives context in authorization check' do
      context_checking_coordinator = Class.new(described_class) do
        protected

        def authorized?(_resource, _action, context = {})
          return true if context[:task_id] == 123

          false
        end
      end

      coordinator = context_checking_coordinator.new(user)

      # Should succeed with matching context
      expect(coordinator.can?('tasker.task', :show, { task_id: 123 })).to be(true)
      expect(coordinator.authorize!('tasker.task', :show, { task_id: 123 })).to be(true)

      # Should fail with different context
      expect(coordinator.can?('tasker.task', :show, { task_id: 456 })).to be(false)
      expect do
        coordinator.authorize!('tasker.task', :show, { task_id: 456 })
      end.to raise_error(Tasker::Authorization::UnauthorizedError)
    end
  end

  describe 'edge cases' do
    before { Tasker.configuration { |config| config.auth { |auth| auth.authorization_enabled = false } } }

    it 'handles nil user gracefully' do
      nil_coordinator = described_class.new(nil)
      expect(nil_coordinator.can?('tasker.task', :show)).to be(true)
      expect(nil_coordinator.authorize!('tasker.task', :show)).to be(true)
    end

    it 'handles empty context' do
      expect(coordinator.can?('tasker.task', :show, {})).to be(true)
    end

    it 'handles nil context' do
      expect(coordinator.can?('tasker.task', :show, nil)).to be(true)
    end
  end
end
