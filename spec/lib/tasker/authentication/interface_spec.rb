# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Authentication::Interface do
  let(:test_class) do
    Class.new do
      include Tasker::Authentication::Interface
    end
  end
  let(:instance) { test_class.new }
  let(:controller) { double('Controller') }

  describe '#authenticate!' do
    it 'raises NotImplementedError by default' do
      expect { instance.authenticate!(controller) }.to raise_error(
        NotImplementedError,
        'Authenticator must implement #authenticate!'
      )
    end
  end

  describe '#current_user' do
    it 'raises NotImplementedError by default' do
      expect { instance.current_user(controller) }.to raise_error(
        NotImplementedError,
        'Authenticator must implement #current_user'
      )
    end
  end

  describe '#authenticated?' do
    context 'when current_user is implemented' do
      before do
        test_class.class_eval do
          def current_user(_controller)
            @test_user
          end

          def set_test_user(user)
            @test_user = user
          end
        end
      end

      it 'returns true when current_user is present' do
        instance.set_test_user(double('User'))
        expect(instance.authenticated?(controller)).to be true
      end

      it 'returns false when current_user is nil' do
        instance.set_test_user(nil)
        expect(instance.authenticated?(controller)).to be false
      end
    end
  end

  describe '#validate_configuration' do
    it 'returns empty array by default' do
      expect(instance.validate_configuration({})).to eq([])
    end

    it 'accepts options parameter' do
      options = { key: 'value' }
      expect(instance.validate_configuration(options)).to eq([])
    end
  end
end
