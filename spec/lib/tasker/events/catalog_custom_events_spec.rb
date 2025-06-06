# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Events::Catalog do
  let(:registry) { Tasker::Events::CustomRegistry.instance }

  before do
    # Clear registry between tests
    registry.clear!
  end

  describe '#complete_catalog' do
    it 'includes both system and custom events' do
      # Register some custom events
      registry.register_event('order.fulfilled', description: 'Order fulfilled')
      registry.register_event('payment.processed', description: 'Payment processed')

      catalog = described_class.complete_catalog

      # Should include system events
      expect(catalog).to have_key('task.completed')
      expect(catalog).to have_key('step.before_handle')

      # Should include custom events
      expect(catalog).to have_key('order.fulfilled')
      expect(catalog).to have_key('payment.processed')

      # Custom events should have proper structure
      expect(catalog['order.fulfilled']).to include(
        name: 'order.fulfilled',
        category: 'custom',
        description: 'Order fulfilled',
        fired_by: [],
        payload_schema: {},
        example_payload: {}
      )
    end

    it 'formats custom events consistently with system events' do
      registry.register_event(
        'inventory.restock_needed',
        description: 'Product needs restocking',
        fired_by: ['InventoryService']
      )

      catalog = described_class.complete_catalog
      custom_event = catalog['inventory.restock_needed']

      expect(custom_event).to have_key(:name)
      expect(custom_event).to have_key(:category)
      expect(custom_event).to have_key(:description)
      expect(custom_event).to have_key(:fired_by)
      expect(custom_event).to have_key(:payload_schema)
      expect(custom_event).to have_key(:example_payload)
    end
  end

  describe '#custom_events' do
    it 'returns only custom events' do
      registry.register_event('order.cancelled', description: 'Order cancelled')
      registry.register_event('payment.refunded', description: 'Payment refunded')

      custom_events = described_class.custom_events

      expect(custom_events.keys).to contain_exactly('order.cancelled', 'payment.refunded')
      expect(custom_events.values).to all(
        include(category: 'custom')
      )
    end

    it 'returns empty hash when no custom events exist' do
      expect(described_class.custom_events).to eq({})
    end
  end

  describe '#search_events' do
    before do
      # Register custom events with different descriptions
      registry.register_event('order.risk_flagged', description: 'Order flagged for risk assessment')
      registry.register_event('payment.failed', description: 'Payment processing failed')
      registry.register_event('inventory.low_stock', description: 'Product inventory running low')
    end

    it 'searches custom events by name' do
      results = described_class.search_events('order')

      expect(results.keys).to include('order.risk_flagged')
      # NOTE: No system events contain 'order' in their names or descriptions
    end

    it 'searches custom events by description' do
      results = described_class.search_events('risk')

      expect(results.keys).to include('order.risk_flagged')
    end

    it 'searches both system and custom events' do
      results = described_class.search_events('failed')

      # Should include custom event
      expect(results.keys).to include('payment.failed')

      # Should also include system events with 'failed' in description
      expect(results.keys).to include('step.failed')
    end

    it 'is case insensitive' do
      results = described_class.search_events('RISK')

      expect(results.keys).to include('order.risk_flagged')
    end
  end

  describe '#events_by_namespace' do
    before do
      registry.register_event('order.created', description: 'Order created')
      registry.register_event('order.fulfilled', description: 'Order fulfilled')
      registry.register_event('payment.processed', description: 'Payment processed')
    end

    it 'returns events matching the namespace' do
      order_events = described_class.events_by_namespace('order')

      expect(order_events.keys).to contain_exactly('order.created', 'order.fulfilled')
    end

    it 'returns empty hash for non-existent namespace' do
      results = described_class.events_by_namespace('nonexistent')

      expect(results).to eq({})
    end

    it 'works with system event namespaces' do
      task_events = described_class.events_by_namespace('task')

      expect(task_events.keys).to include('task.completed', 'task.failed', 'task.initialize_requested')
    end
  end

  describe 'Events module delegation' do
    before do
      registry.register_event('subscription.activated', description: 'Subscription activated')
    end

    it 'delegates complete_catalog correctly' do
      catalog = Tasker::Events.complete_catalog

      expect(catalog).to have_key('subscription.activated')
      expect(catalog).to have_key('task.completed')
    end

    it 'delegates custom_events correctly' do
      custom_events = Tasker::Events.custom_events

      expect(custom_events.keys).to contain_exactly('subscription.activated')
    end

    it 'delegates search_events correctly' do
      results = Tasker::Events.search_events('subscription')

      expect(results).to have_key('subscription.activated')
    end

    it 'delegates events_by_namespace correctly' do
      results = Tasker::Events.events_by_namespace('subscription')

      expect(results).to have_key('subscription.activated')
    end
  end

  describe 'integration with print_catalog' do
    it 'includes custom events in printed catalog' do
      registry.register_event('user.login', description: 'User logged in')

      expect { described_class.print_catalog }.to output(/user\.login/).to_stdout
    end
  end
end
