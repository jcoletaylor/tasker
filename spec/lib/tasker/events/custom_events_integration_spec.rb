# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Custom Events Automatic Discovery', type: :integration do
  let(:custom_registry) { instance_double(Tasker::Events::CustomRegistry) }
  let(:handler_factory) { instance_double(Tasker::HandlerFactory) }

  before do
    # Mock the CustomRegistry singleton to avoid state pollution
    allow(Tasker::Events::CustomRegistry).to receive(:instance).and_return(custom_registry)

    # Set up common mock behaviors for CustomRegistry
    allow(custom_registry).to receive(:register_event)

    # Store original handler classes for cleanup
    @original_handler_classes = Tasker::HandlerFactory.instance.handler_classes.dup
  end

  after do
    # Clean up any test handlers to avoid state leakage
    real_factory = Tasker::HandlerFactory.instance
    test_keys = real_factory.handler_classes.keys - @original_handler_classes.keys
    test_keys.each { |key| real_factory.handler_classes.delete(key) }
  end

  describe 'Class-based custom event discovery' do
    let(:step_handler_class) do
      Class.new(Tasker::StepHandler::Base) do
        def self.name
          'TestStepHandler'
        end

        def self.custom_event_configuration
          [
            {
              name: 'payment.processed',
              description: 'Published when payment processing completes'
            },
            {
              name: 'payment.risk_flagged',
              description: 'Published when payment is flagged for review'
            }
          ]
        end

        def process(_task, _sequence, _step)
          { status: 'completed' }
        end
      end
    end

    let(:task_handler_class) do
      step_class = step_handler_class
      Class.new do
        include Tasker::TaskHandler

        def self.name
          'TestTaskHandler'
        end

        define_step_templates do |t|
          t.define(
            name: 'process_payment',
            description: 'Process payment',
            handler_class: step_class
          )
        end
      end
    end

    it 'automatically discovers and registers custom events when task handler is registered' do
      # Use the real HandlerFactory but mock the CustomRegistry
      real_factory = Tasker::HandlerFactory.instance

      # Register the task handler - this should trigger automatic discovery
      real_factory.register('test_task', task_handler_class)

      # Verify events were automatically registered through our mock
      expect(custom_registry).to have_received(:register_event).with(
        'payment.processed',
        description: 'Published when payment processing completes',
        fired_by: ['TestStepHandler']
      )

      expect(custom_registry).to have_received(:register_event).with(
        'payment.risk_flagged',
        description: 'Published when payment is flagged for review',
        fired_by: ['TestStepHandler']
      )
    end
  end

  describe 'YAML-based custom event discovery' do
    let(:step_handler_class) do
      Class.new(Tasker::StepHandler::Base) do
        def self.name
          'YamlStepHandler'
        end

        def process(_task, _sequence, _step)
          { status: 'completed' }
        end
      end
    end

    let(:task_handler_class) do
      step_class = step_handler_class
      Class.new do
        include Tasker::TaskHandler

        def self.name
          'YamlTaskHandler'
        end

        define_step_templates do |t|
          t.define(
            name: 'data_processing',
            description: 'Process data',
            handler_class: step_class,
            custom_events: [
              {
                name: 'data.processed',
                description: 'Published when data processing completes'
              },
              {
                name: 'data.validation_failed',
                description: 'Published when data validation fails'
              }
            ]
          )
        end
      end
    end

    it 'automatically discovers and registers YAML-configured custom events' do
      # Use the real HandlerFactory but mock the CustomRegistry
      real_factory = Tasker::HandlerFactory.instance

      # Register the task handler - this should trigger automatic discovery
      real_factory.register('yaml_task', task_handler_class)

      # Verify events were automatically registered through our mock
      expect(custom_registry).to have_received(:register_event).with(
        'data.processed',
        description: 'Published when data processing completes',
        fired_by: ['YamlStepHandler']
      )

      expect(custom_registry).to have_received(:register_event).with(
        'data.validation_failed',
        description: 'Published when data validation fails',
        fired_by: ['YamlStepHandler']
      )
    end
  end

  describe 'Hybrid class and YAML event discovery' do
    let(:step_handler_class) do
      Class.new(Tasker::StepHandler::Base) do
        def self.name
          'HybridStepHandler'
        end

        def self.custom_event_configuration
          [
            {
              name: 'handler.class_defined',
              description: 'Event defined in handler class'
            }
          ]
        end

        def process(_task, _sequence, _step)
          { status: 'completed' }
        end
      end
    end

    let(:task_handler_class) do
      step_class = step_handler_class
      Class.new do
        include Tasker::TaskHandler

        def self.name
          'HybridTaskHandler'
        end

        define_step_templates do |t|
          t.define(
            name: 'hybrid_processing',
            description: 'Hybrid processing',
            handler_class: step_class,
            custom_events: [
              {
                name: 'template.yaml_defined',
                description: 'Event defined in YAML template'
              }
            ]
          )
        end
      end
    end

    it 'discovers and registers both class-based and YAML-based events' do
      # Use the real HandlerFactory but mock the CustomRegistry
      real_factory = Tasker::HandlerFactory.instance

      # Register the task handler - this should trigger automatic discovery
      real_factory.register('hybrid_task', task_handler_class)

      # Verify both types of events were registered through our mock
      expect(custom_registry).to have_received(:register_event).with(
        'handler.class_defined',
        description: 'Event defined in handler class',
        fired_by: ['HybridStepHandler']
      )

      expect(custom_registry).to have_received(:register_event).with(
        'template.yaml_defined',
        description: 'Event defined in YAML template',
        fired_by: ['HybridStepHandler']
      )
    end
  end

  describe 'Error handling - Fail Fast Philosophy' do
    let(:broken_step_handler_class) do
      Class.new(Tasker::StepHandler::Base) do
        def self.name
          'BrokenStepHandler'
        end

        def self.custom_event_configuration
          raise StandardError, 'Simulated configuration error'
        end

        def process(_task, _sequence, _step)
          { status: 'completed' }
        end
      end
    end

    let(:broken_task_handler_class) do
      step_class = broken_step_handler_class
      Class.new do
        include Tasker::TaskHandler

        def self.name
          'BrokenTaskHandler'
        end

        define_step_templates do |t|
          t.define(
            name: 'broken_step',
            description: 'Broken step',
            handler_class: step_class
          )
        end
      end
    end

    it 'fails fast when custom event configuration is broken - no silent failures' do
      # Use the real HandlerFactory to test error handling
      real_factory = Tasker::HandlerFactory.instance

      # Configuration failures should be visible errors, not silently swallowed
      expect do
        real_factory.register('broken_task', broken_task_handler_class)
      end.to raise_error(StandardError, 'Simulated configuration error')

      # Task handler should NOT be registered when configuration fails
      default_namespace = real_factory.handler_classes['default']
      if default_namespace
        expect(default_namespace).not_to have_key(:broken_task)
      else
        # If default namespace doesn't exist, that's also fine - no handlers were registered
        expect(default_namespace).to be_nil
      end
    end

    it 'provides clear error messages for configuration failures' do
      real_factory = Tasker::HandlerFactory.instance

      expect do
        real_factory.register('broken_task', broken_task_handler_class)
      end.to raise_error do |error|
        expect(error.message).to include('Simulated configuration error')
        expect(error).to be_a(StandardError)
      end
    end
  end

  describe 'Integration with existing event system' do
    let(:step_handler_class) do
      Class.new(Tasker::StepHandler::Base) do
        def self.name
          'IntegrationStepHandler'
        end

        def self.custom_event_configuration
          [
            {
              name: 'integration.test_event',
              description: 'Test event for integration'
            }
          ]
        end

        def process(_task, _sequence, step)
          # Publish the custom event
          publish_custom_event('integration.test_event', {
                                 step_id: step.id,
                                 status: 'success'
                               })
          { status: 'completed' }
        end
      end
    end

    let(:task_handler_class) do
      step_class = step_handler_class
      Class.new do
        include Tasker::TaskHandler

        def self.name
          'IntegrationTaskHandler'
        end

        define_step_templates do |t|
          t.define(
            name: 'integration_step',
            description: 'Integration step',
            handler_class: step_class
          )
        end
      end
    end

    it 'integrates with the complete event catalog system' do
      # Use the real HandlerFactory but mock the CustomRegistry
      real_factory = Tasker::HandlerFactory.instance

      # Register the task handler - this should trigger automatic discovery
      real_factory.register('integration_task', task_handler_class)

      # Verify that the custom registry was called to register the event
      expect(custom_registry).to have_received(:register_event).with(
        'integration.test_event',
        description: 'Test event for integration',
        fired_by: ['IntegrationStepHandler']
      )
    end
  end
end
