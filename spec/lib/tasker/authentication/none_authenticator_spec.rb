# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Authentication::NoneAuthenticator do
  let(:authenticator) { described_class.new }
  let(:controller) { double('Controller') }

  describe 'interface implementation' do
    it 'includes the Authentication::Interface' do
      expect(authenticator).to respond_to(:authenticate!)
      expect(authenticator).to respond_to(:current_user)
      expect(authenticator).to respond_to(:authenticated?)
    end
  end

  describe '#authenticate!' do
    it 'always succeeds and returns true' do
      expect(authenticator.authenticate!(controller)).to be true
    end

    it 'does not raise any errors' do
      expect { authenticator.authenticate!(controller) }.not_to raise_error
    end
  end

  describe '#current_user' do
    it 'always returns nil' do
      expect(authenticator.current_user(controller)).to be_nil
    end
  end

  describe '#authenticated?' do
    it 'always returns true (no-auth mode considers everyone authenticated)' do
      expect(authenticator.authenticated?(controller)).to be true
    end
  end
end
