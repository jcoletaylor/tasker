# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../examples/test_authenticator'

RSpec.describe Tasker::Concerns::Authenticatable do
  let(:controller_class) do
    Class.new do
      attr_reader :action_executed

      def self.before_action(method, options = {})
        # Mock before_action behavior
        @before_action_method = method
        @before_action_options = options
      end

      def self.get_before_action_info
        [@before_action_method, @before_action_options]
      end

      def initialize
        @before_action_called = false
        @action_executed = false
      end

      def execute_action
        # Simulate action execution which would trigger before_action
        method, options = self.class.get_before_action_info
        send(method) unless options[:unless] && send(options[:unless])
        @action_executed = true
      end

      include Tasker::Concerns::Authenticatable
    end
  end

  let(:controller) { controller_class.new }

  # Isolate singleton state to prevent test pollution
  around do |example|
    original_config = Tasker::Configuration.instance_variable_get(:@configuration)
    # Reset coordinator and test authenticator state
    Tasker::Authentication::Coordinator.reset!
    TestAuthenticator.reset!

    example.run
  ensure
    # Restore original configuration and reset state
    Tasker::Configuration.instance_variable_set(:@configuration, original_config)
    Tasker::Authentication::Coordinator.reset!
    TestAuthenticator.reset!
  end

  describe 'included behavior' do
    it 'sets up before_action for authenticate_tasker_user!' do
      method, options = controller_class.get_before_action_info
      expect(method).to eq(:authenticate_tasker_user!)
      expect(options[:unless]).to eq(:skip_authentication?)
    end
  end

  describe '#authenticate_tasker_user!' do
    context 'when authentication is skipped' do
      before do
        Tasker.configuration.auth.authentication_enabled = false
      end

      it 'returns true without calling authenticator' do
        expect(Tasker::Authentication::Coordinator).not_to receive(:authenticate!)
        expect(controller.send(:authenticate_tasker_user!)).to be true
      end
    end

    context 'when authentication is required' do
      before do
        Tasker.configuration.auth.authentication_enabled = true
        Tasker.configuration.auth.authenticator_class = 'TestAuthenticator'
      end

      it 'calls the authentication coordinator' do
        expect(Tasker::Authentication::Coordinator).to receive(:authenticate!).with(controller)
        controller.send(:authenticate_tasker_user!)
      end

      context 'when authentication succeeds' do
        before do
          TestAuthenticator.set_authentication_result(true)
        end

        it 'does not raise an error' do
          expect { controller.send(:authenticate_tasker_user!) }.not_to raise_error
        end
      end

      context 'when authentication fails' do
        before do
          TestAuthenticator.set_authentication_result(false)
        end

        it 'raises an authentication error' do
          expect { controller.send(:authenticate_tasker_user!) }.to raise_error(
            Tasker::Authentication::AuthenticationError
          )
        end
      end
    end
  end

  describe '#current_tasker_user' do
    before do
      Tasker.configuration.auth.authentication_enabled = true
      Tasker.configuration.auth.authenticator_class = 'TestAuthenticator'
    end

    it 'delegates to authentication coordinator' do
      user = TestUser.new
      TestAuthenticator.set_current_user(user)

      expect(controller.send(:current_tasker_user)).to eq(user)
    end

    it 'memoizes the result' do
      user = TestUser.new
      TestAuthenticator.set_current_user(user)

      # First call
      first_result = controller.send(:current_tasker_user)

      # Change the user in the authenticator
      TestAuthenticator.set_current_user(TestUser.new(id: 2))

      # Second call should return the memoized result
      second_result = controller.send(:current_tasker_user)

      expect(first_result).to eq(second_result)
      expect(first_result.id).to eq(1) # Original user
    end
  end

  describe '#tasker_user_authenticated?' do
    before do
      Tasker.configuration.auth.authentication_enabled = true
      Tasker.configuration.auth.authenticator_class = 'TestAuthenticator'
    end

    it 'delegates to authentication coordinator' do
      TestAuthenticator.set_current_user(TestUser.new)

      expect(controller.send(:tasker_user_authenticated?)).to be true
    end

    it 'returns false when no user is set' do
      TestAuthenticator.set_current_user(nil)

      expect(controller.send(:tasker_user_authenticated?)).to be false
    end
  end

  describe '#skip_authentication?' do
    context 'when authentication is disabled' do
      before do
        Tasker.configuration.auth.authentication_enabled = false
      end

      it 'returns true' do
        expect(controller.send(:skip_authentication?)).to be true
      end
    end

    context 'when authentication is enabled' do
      before do
        Tasker.configuration.auth.authentication_enabled = true
        Tasker.configuration.auth.authenticator_class = 'TestAuthenticator'
      end

      it 'returns false' do
        expect(controller.send(:skip_authentication?)).to be false
      end
    end
  end

  describe 'integration with before_action' do
    context 'when authentication should be skipped' do
      before do
        Tasker.configuration.auth.authentication_enabled = false
      end

      it 'skips authentication when executing action' do
        expect(controller).not_to receive(:authenticate_tasker_user!)
        controller.execute_action
        expect(controller.action_executed).to be true
      end
    end

    context 'when authentication is required' do
      before do
        Tasker.configuration.auth.authentication_enabled = true
        Tasker.configuration.auth.authenticator_class = 'TestAuthenticator'
        TestAuthenticator.set_authentication_result(true)
      end

      it 'calls authentication before executing action' do
        expect(controller).to receive(:authenticate_tasker_user!).and_call_original
        controller.execute_action
        expect(controller.action_executed).to be true
      end
    end
  end
end
