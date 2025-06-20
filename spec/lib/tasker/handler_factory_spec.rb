# typed: false
# frozen_string_literal: true

require 'rails_helper'

# Test handler class that can be constantized
class TestStringHandler
  def initialize
    # Test handler initialization
  end
end

module Tasker
  RSpec.describe HandlerFactory do
    let(:factory) { described_class.instance }

    # Test handler classes for namespacing tests
    let(:payment_handler_class) do
      Class.new do
        def self.name
          'PaymentOrderHandler'
        end
      end
    end

    let(:inventory_handler_class) do
      Class.new do
        def self.name
          'InventoryOrderHandler'
        end
      end
    end

    let(:legacy_handler_class) do
      Class.new do
        def self.name
          'LegacyHandler'
        end
      end
    end

    before do
      # Store original handler classes for surgical cleanup
      @original_handler_classes = factory.handler_classes.deep_dup
      @original_namespaces = factory.namespaces.dup
    end

    after do
      # Surgical cleanup - only remove test-specific handlers
      test_namespaces = factory.namespaces - @original_namespaces
      test_namespaces.each { |namespace| factory.handler_classes.delete(namespace) }

      # Remove test handlers from existing namespaces
      @original_handler_classes.each do |namespace, handlers|
        if factory.handler_classes[namespace]
          test_handlers = factory.handler_classes[namespace].keys - handlers.keys
          test_handlers.each { |handler| factory.handler_classes[namespace].delete(handler) }
        end
      end

      # Restore original namespaces
      factory.namespaces.clear
      @original_namespaces.each { |namespace| factory.namespaces.add(namespace) }
    end

    describe '#initialize' do
      it 'initializes with default namespace in namespaces set' do
        # Since HandlerFactory is a singleton, we test the current instance state
        expect(factory.namespaces).to include('default_system')
        expect(factory.handler_classes).to be_a(Hash)
      end
    end

    describe '#register' do
      context 'with default_system (backward compatibility)' do
        it 'registers handler in default_system when no dependent_system specified' do
          factory.register('legacy_task', legacy_handler_class)

          expect(factory.handler_classes['default_system']).to have_key(:legacy_task)
          expect(factory.handler_classes['default_system'][:legacy_task]).to eq(legacy_handler_class)
          expect(factory.namespaces).to include('default_system')
        end

        it 'handles string class names' do
          factory.register('string_task', 'TestStringHandler')

          expect(factory.handler_classes['default_system'][:string_task]).to eq('TestStringHandler')
        end
      end

      context 'with explicit dependent_system' do
        it 'registers handler in specified dependent system' do
          factory.register('process_order', payment_handler_class, dependent_system: 'payments')

          expect(factory.handler_classes['payments']).to have_key(:process_order)
          expect(factory.handler_classes['payments'][:process_order]).to eq(payment_handler_class)
          expect(factory.namespaces).to include('payments')
        end

        it 'allows same name in different dependent systems' do
          factory.register('process_order', payment_handler_class, dependent_system: 'payments')
          factory.register('process_order', inventory_handler_class, dependent_system: 'inventory')

          expect(factory.handler_classes['payments'][:process_order]).to eq(payment_handler_class)
          expect(factory.handler_classes['inventory'][:process_order]).to eq(inventory_handler_class)
          expect(factory.namespaces).to include('payments', 'inventory')
        end

        it 'converts dependent_system to string' do
          factory.register('symbol_task', payment_handler_class, dependent_system: :payments)

          expect(factory.handler_classes['payments']).to have_key(:symbol_task)
          expect(factory.namespaces).to include('payments')
        end

        it 'initializes namespace if it does not exist' do
          expect(factory.handler_classes).not_to have_key('new_system')

          factory.register('new_task', payment_handler_class, dependent_system: 'new_system')

          expect(factory.handler_classes).to have_key('new_system')
          expect(factory.namespaces).to include('new_system')
        end
      end

      context 'custom event configuration - fail fast error handling' do
        let(:broken_handler_class) do
          Class.new do
            def self.name
              'BrokenHandler'
            end

            def self.custom_event_configuration
              raise StandardError, 'Configuration is broken'
            end
          end
        end

        let(:working_handler_class) do
          Class.new do
            def self.name
              'WorkingHandler'
            end

            def self.custom_event_configuration
              [
                { name: 'test.event', description: 'Test event' }
              ]
            end
          end
        end

        it 'fails fast when custom event configuration raises an error' do
          expect do
            factory.register('broken_handler', broken_handler_class)
          end.to raise_error(StandardError, 'Configuration is broken')

          # Handler should NOT be registered when configuration fails
          # Due to atomic registration, the default_system key may not even exist
          default_handlers = factory.handler_classes['default_system'] || {}
          expect(default_handlers).not_to have_key(:broken_handler)
        end

        it 'provides clear error messages for configuration failures' do
          expect do
            factory.register('broken_handler', broken_handler_class, dependent_system: 'payments')
          end.to raise_error do |error|
            expect(error.message).to eq('Configuration is broken')
            expect(error).to be_a(StandardError)
          end

          # Namespace should not be polluted with failed registrations
          expect(factory.handler_classes).not_to have_key('payments')
        end

        it 'successfully registers handlers with valid custom event configuration' do
          # Mock the custom registry to avoid actual event registration in this unit test
          custom_registry = instance_double(Tasker::Events::CustomRegistry)
          allow(Tasker::Events::CustomRegistry).to receive(:instance).and_return(custom_registry)
          allow(custom_registry).to receive(:register_event)

          expect do
            factory.register('working_handler', working_handler_class)
          end.not_to raise_error

          # Handler should be successfully registered
          expect(factory.handler_classes['default_system']).to have_key(:working_handler)
          expect(factory.handler_classes['default_system'][:working_handler]).to eq(working_handler_class)
        end

        it 'preserves atomicity - no partial registration on configuration failure' do
          original_handlers = factory.handler_classes.deep_dup
          original_namespaces = factory.namespaces.dup

          expect do
            factory.register('broken_handler', broken_handler_class, dependent_system: 'new_system')
          end.to raise_error(StandardError, 'Configuration is broken')

          # Factory state should be unchanged after failure
          expect(factory.handler_classes).to eq(original_handlers)
          expect(factory.namespaces).to eq(original_namespaces)
        end
      end
    end

    describe '#get' do
      before do
        factory.register('legacy_task', legacy_handler_class)
        factory.register('process_order', payment_handler_class, dependent_system: 'payments')
        factory.register('process_order', inventory_handler_class, dependent_system: 'inventory')
      end

      context 'with default_system (backward compatibility)' do
        it 'retrieves handler from default_system when no dependent_system specified' do
          handler = factory.get('legacy_task')

          expect(handler).to be_a(legacy_handler_class)
        end

        it 'retrieves handler from default_system when explicitly specified' do
          handler = factory.get('legacy_task', dependent_system: 'default_system')

          expect(handler).to be_a(legacy_handler_class)
        end
      end

      context 'with explicit dependent_system' do
        it 'retrieves handler from specified dependent system' do
          payment_handler = factory.get('process_order', dependent_system: 'payments')
          inventory_handler = factory.get('process_order', dependent_system: 'inventory')

          expect(payment_handler).to be_a(payment_handler_class)
          expect(inventory_handler).to be_a(inventory_handler_class)
        end

        it 'converts dependent_system to string' do
          handler = factory.get('process_order', dependent_system: :payments)

          expect(handler).to be_a(payment_handler_class)
        end
      end

      context 'error handling' do
        it 'raises appropriate error for missing handler in default_system' do
          expect do
            factory.get('nonexistent')
          end.to raise_error(ProceduralError, 'No task handler for nonexistent')
        end

        it 'raises appropriate error for missing handler in specific dependent_system' do
          expect do
            factory.get('nonexistent', dependent_system: 'payments')
          end.to raise_error(ProceduralError, 'No task handler for nonexistent in dependent system payments')
        end

        it 'raises error when handler exists in different dependent_system' do
          expect do
            factory.get('process_order', dependent_system: 'nonexistent_system')
          end.to raise_error(ProceduralError,
                             'No task handler for process_order in dependent system nonexistent_system')
        end
      end

      context 'string class instantiation' do
        it 'handles string class names during registration' do
          # Test that string class names are stored correctly
          # The actual instantiation will be tested with real classes in integration tests
          factory.register('string_task', 'TestStringHandler')

          expect(factory.handler_classes['default_system'][:string_task]).to eq('TestStringHandler')
        end
      end
    end

    describe '#list_handlers' do
      before do
        factory.register('legacy_task', legacy_handler_class)
        factory.register('payment_task', payment_handler_class, dependent_system: 'payments')
        factory.register('inventory_task', inventory_handler_class, dependent_system: 'inventory')
        factory.register('process_order', payment_handler_class, dependent_system: 'payments')
      end

      it 'returns all handlers when no namespace specified' do
        all_handlers = factory.list_handlers

        expect(all_handlers).to have_key('default_system')
        expect(all_handlers).to have_key('payments')
        expect(all_handlers).to have_key('inventory')
        expect(all_handlers['default_system']).to have_key(:legacy_task)
        expect(all_handlers['payments']).to have_key(:payment_task)
        expect(all_handlers['payments']).to have_key(:process_order)
        expect(all_handlers['inventory']).to have_key(:inventory_task)
      end

      it 'returns handlers for specific namespace' do
        payment_handlers = factory.list_handlers(namespace: 'payments')

        expect(payment_handlers).to have_key(:payment_task)
        expect(payment_handlers).to have_key(:process_order)
        expect(payment_handlers).not_to have_key(:legacy_task)
        expect(payment_handlers).not_to have_key(:inventory_task)
      end

      it 'returns empty hash for nonexistent namespace' do
        empty_handlers = factory.list_handlers(namespace: 'nonexistent')

        expect(empty_handlers).to eq({})
      end

      it 'converts namespace to string' do
        payment_handlers = factory.list_handlers(namespace: :payments)

        expect(payment_handlers).to have_key(:payment_task)
        expect(payment_handlers).to have_key(:process_order)
      end
    end

    describe '#registered_namespaces' do
      it 'returns default_system initially' do
        expect(factory.registered_namespaces).to eq(['default_system'])
      end

      it 'includes all registered namespaces' do
        factory.register('legacy_task', legacy_handler_class)
        factory.register('payment_task', payment_handler_class, dependent_system: 'payments')
        factory.register('inventory_task', inventory_handler_class, dependent_system: 'inventory')

        namespaces = factory.registered_namespaces
        expect(namespaces).to include('default_system', 'payments', 'inventory')
        expect(namespaces.length).to eq(3)
      end
    end

    describe 'custom event discovery integration' do
      let(:event_handler_class) do
        Class.new do
          def self.name
            'EventHandler'
          end

          def self.custom_event_configuration
            [
              { name: 'test.event', description: 'Test event' }
            ]
          end
        end
      end

      it 'preserves custom event discovery functionality' do
        expect(factory).to receive(:discover_and_register_custom_events).with(event_handler_class)

        factory.register('event_task', event_handler_class, dependent_system: 'events')
      end
    end

    describe 'backward compatibility' do
      it 'maintains complete backward compatibility with existing API' do
        # This test ensures that all existing code continues to work unchanged

        # Existing registration pattern
        factory.register('legacy_task', legacy_handler_class)

        # Existing retrieval pattern
        handler = factory.get('legacy_task')

        expect(handler).to be_a(legacy_handler_class)
        expect(factory.handler_classes['default_system']).to have_key(:legacy_task)
      end
    end
  end
end
