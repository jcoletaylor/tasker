# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::ProceduralError do
  describe 'inheritance hierarchy' do
    it 'inherits from Tasker::Error' do
      expect(described_class.superclass).to eq(Tasker::Error)
    end
  end

  describe 'basic error creation' do
    it 'can be raised with a message' do
      expect { raise described_class, 'test error' }.to raise_error(described_class, 'test error')
    end
  end
end

RSpec.describe Tasker::RetryableError do
  describe 'inheritance' do
    it 'inherits from ProceduralError' do
      expect(described_class.superclass).to eq(Tasker::ProceduralError)
    end
  end

  describe 'initialization' do
    it 'can be created with just a message' do
      error = described_class.new('test error')
      expect(error.message).to eq('test error')
      expect(error.retry_after).to be_nil
      expect(error.context).to eq({})
    end

    it 'can be created with retry_after' do
      error = described_class.new('rate limited', retry_after: 60)
      expect(error.message).to eq('rate limited')
      expect(error.retry_after).to eq(60)
      expect(error.context).to eq({})
    end

    it 'can be created with context' do
      context = { service: 'billing_api', error_code: 503 }
      error = described_class.new('service unavailable', context: context)
      expect(error.message).to eq('service unavailable')
      expect(error.retry_after).to be_nil
      expect(error.context).to eq(context)
    end

    it 'can be created with both retry_after and context' do
      context = { service: 'payment_api', user_id: 123 }
      error = described_class.new('timeout', retry_after: 30, context: context)
      expect(error.message).to eq('timeout')
      expect(error.retry_after).to eq(30)
      expect(error.context).to eq(context)
    end
  end

  describe 'usage examples' do
    it 'supports basic retryable error pattern' do
      expect { raise described_class, 'Payment service timeout' }
        .to raise_error(described_class, 'Payment service timeout')
    end

    it 'supports rate limiting pattern' do
      error = nil
      begin
        raise described_class.new('Rate limited', retry_after: 60)
      rescue described_class => e
        error = e
      end

      expect(error.message).to eq('Rate limited')
      expect(error.retry_after).to eq(60)
    end

    it 'supports monitoring context pattern' do
      error = nil
      begin
        raise described_class.new(
          'External API unavailable',
          retry_after: 30,
          context: { service: 'billing_api', error_code: 503 }
        )
      rescue described_class => e
        error = e
      end

      expect(error.message).to eq('External API unavailable')
      expect(error.retry_after).to eq(30)
      expect(error.context).to eq({ service: 'billing_api', error_code: 503 })
    end
  end
end

RSpec.describe Tasker::PermanentError do
  describe 'inheritance' do
    it 'inherits from ProceduralError' do
      expect(described_class.superclass).to eq(Tasker::ProceduralError)
    end
  end

  describe 'initialization' do
    it 'can be created with just a message' do
      error = described_class.new('invalid user ID')
      expect(error.message).to eq('invalid user ID')
      expect(error.error_code).to be_nil
      expect(error.context).to eq({})
    end

    it 'can be created with error_code' do
      error = described_class.new('insufficient funds', error_code: 'INSUFFICIENT_FUNDS')
      expect(error.message).to eq('insufficient funds')
      expect(error.error_code).to eq('INSUFFICIENT_FUNDS')
      expect(error.context).to eq({})
    end

    it 'can be created with context' do
      context = { user_id: 123, operation: 'admin_access' }
      error = described_class.new('not authorized', context: context)
      expect(error.message).to eq('not authorized')
      expect(error.error_code).to be_nil
      expect(error.context).to eq(context)
    end

    it 'can be created with both error_code and context' do
      context = { user_id: 456, account_id: 789 }
      error = described_class.new('access denied', error_code: 'ACCESS_DENIED', context: context)
      expect(error.message).to eq('access denied')
      expect(error.error_code).to eq('ACCESS_DENIED')
      expect(error.context).to eq(context)
    end
  end

  describe 'usage examples' do
    it 'supports basic permanent error pattern' do
      expect { raise described_class, 'Invalid user ID format' }
        .to raise_error(described_class, 'Invalid user ID format')
    end

    it 'supports error categorization pattern' do
      error = nil
      begin
        raise described_class.new(
          'Insufficient funds for transaction',
          error_code: 'INSUFFICIENT_FUNDS'
        )
      rescue described_class => e
        error = e
      end

      expect(error.message).to eq('Insufficient funds for transaction')
      expect(error.error_code).to eq('INSUFFICIENT_FUNDS')
    end

    it 'supports monitoring context pattern' do
      error = nil
      begin
        raise described_class.new(
          'User not authorized for this operation',
          error_code: 'AUTHORIZATION_FAILED',
          context: { user_id: 123, operation: 'admin_access' }
        )
      rescue described_class => e
        error = e
      end

      expect(error.message).to eq('User not authorized for this operation')
      expect(error.error_code).to eq('AUTHORIZATION_FAILED')
      expect(error.context).to eq({ user_id: 123, operation: 'admin_access' })
    end
  end
end
