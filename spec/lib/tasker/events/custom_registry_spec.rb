# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Events::CustomRegistry do
  let(:registry) { described_class.instance }

  before do
    # Clear registry between tests
    registry.clear!
  end

  describe '#register_event' do
    it 'registers a valid custom event' do
      expect do
        registry.register_event(
          'order.fulfilled',
          description: 'Order has been fulfilled',
          fired_by: ['OrderService']
        )
      end.not_to raise_error

      expect(registry.registered?('order.fulfilled')).to be true
    end

    it 'stores event metadata correctly' do
      registry.register_event(
        'payment.processed',
        description: 'Payment has been processed',
        fired_by: %w[PaymentService BillingService]
      )

      metadata = registry.event_metadata('payment.processed')
      expect(metadata).to include(
        name: 'payment.processed',
        category: 'custom',
        description: 'Payment has been processed',
        fired_by: %w[PaymentService BillingService]
      )
      expect(metadata[:registered_at]).to be_present
    end

    it 'requires namespaced event names' do
      expect do
        registry.register_event('invalid_event_name')
      end.to raise_error(ArgumentError, /must contain a namespace/)
    end

    it 'prevents conflicts with system events' do
      expect do
        registry.register_event('task.completed')
      end.to raise_error(ArgumentError, /conflicts with system event/)
    end

    it 'prevents use of reserved namespaces' do
      reserved_namespaces = %w[task step workflow observability test]

      reserved_namespaces.each do |namespace|
        expect do
          registry.register_event("#{namespace}.custom_event")
        end.to raise_error(ArgumentError, /reserved for system events/)
      end
    end

    it 'handles duplicate registrations gracefully' do
      registry.register_event('order.created')

      expect(Rails.logger).to receive(:warn).with(/already registered/)
      registry.register_event('order.created')
    end

    it 'validates event name types' do
      expect do
        registry.register_event(123)
      end.to raise_error(ArgumentError, /must be a string/)
    end
  end

  describe '#custom_events' do
    it 'returns empty hash when no events registered' do
      expect(registry.custom_events).to eq({})
    end

    it 'returns all registered custom events' do
      registry.register_event('order.fulfilled', description: 'Order fulfilled')
      registry.register_event('payment.processed', description: 'Payment processed')

      events = registry.custom_events
      expect(events.keys).to contain_exactly('order.fulfilled', 'payment.processed')
    end

    it 'returns a copy to prevent external modification' do
      registry.register_event('order.fulfilled')

      events = registry.custom_events
      events['malicious.event'] = { name: 'malicious.event' }

      expect(registry.custom_events.keys).to contain_exactly('order.fulfilled')
    end
  end

  describe '#registered?' do
    it 'returns true for registered events' do
      registry.register_event('order.fulfilled')
      expect(registry.registered?('order.fulfilled')).to be true
    end

    it 'returns false for unregistered events' do
      expect(registry.registered?('nonexistent.event')).to be false
    end
  end

  describe '#event_metadata' do
    it 'returns metadata for registered events' do
      registry.register_event('order.fulfilled', description: 'Test event')

      metadata = registry.event_metadata('order.fulfilled')
      expect(metadata).to be_a(Hash)
      expect(metadata[:name]).to eq('order.fulfilled')
    end

    it 'returns nil for unregistered events' do
      expect(registry.event_metadata('nonexistent.event')).to be_nil
    end
  end

  describe '#clear!' do
    it 'removes all registered events' do
      registry.register_event('order.fulfilled')
      registry.register_event('payment.processed')

      expect(registry.custom_events.size).to eq(2)

      registry.clear!

      expect(registry.custom_events).to be_empty
    end
  end

  describe 'singleton behavior' do
    it 'returns the same instance' do
      instance1 = described_class.instance
      instance2 = described_class.instance

      expect(instance1).to be(instance2)
    end

    it 'prevents direct instantiation' do
      expect { described_class.new }.to raise_error(NoMethodError)
    end
  end

  describe 'integration with dry-events publisher' do
    it 'registers events with the publisher' do
      publisher = Tasker::Events::Publisher.instance

      expect(publisher).to receive(:register_event).with('order.fulfilled')

      registry.register_event('order.fulfilled')
    end
  end
end
