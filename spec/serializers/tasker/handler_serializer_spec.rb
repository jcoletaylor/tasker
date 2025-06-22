# typed: false
# frozen_string_literal: true

require 'rails_helper'

module Tasker
  RSpec.describe HandlerSerializer, type: :serializer do
    # Test handler class with step templates
    let(:test_handler_class) do
      Class.new do
        def self.name
          'TestHandlerClass'
        end

        def step_templates
          [
            Tasker::Types::StepTemplate.new(
              name: 'first_step',
              dependent_system: 'test_system',
              description: 'First step in the workflow',
              handler_class: String,
              handler_config: { timeout: 30 },
              depends_on_step: nil
            ),
            Tasker::Types::StepTemplate.new(
              name: 'second_step',
              dependent_system: 'test_system',
              description: 'Second step in the workflow',
              handler_class: String,
              handler_config: { retry_limit: 3 },
              depends_on_step: 'first_step'
            )
          ]
        end
      end
    end

    # Handler class without step templates (should handle gracefully)
    let(:minimal_handler_class) do
      Class.new do
        def self.name
          'MinimalHandlerClass'
        end

        def step_templates
          []
        end
      end
    end

    # Handler class that raises an error during instantiation
    let(:error_handler_class) do
      Class.new do
        def self.name
          'ErrorHandlerClass'
        end

        def initialize
          raise StandardError, 'Instantiation error'
        end

        def step_templates
          []
        end
      end
    end

    describe '#serializable_hash' do
      context 'with full handler information' do
        let(:serializer) do
          described_class.new(
            test_handler_class,
            handler_name: 'test_handler',
            namespace: 'payments',
            version: '1.0.0'
          )
        end

        let(:serialized_data) { serializer.serializable_hash }

        it 'includes basic handler information' do
          expect(serialized_data[:name]).to eq('test_handler')
          expect(serialized_data[:namespace]).to eq('payments')
          expect(serialized_data[:version]).to eq('1.0.0')
          expect(serialized_data[:full_name]).to eq('payments.test_handler@1.0.0')
          expect(serialized_data[:class_name]).to eq('TestHandlerClass')
        end

        it 'indicates handler is available' do
          expect(serialized_data[:available]).to be(true)
        end

        it 'includes step templates with full details' do
          expect(serialized_data[:step_templates]).to be_an(Array)
          expect(serialized_data[:step_templates].size).to eq(2)

          first_step = serialized_data[:step_templates][0]
          expect(first_step[:name]).to eq('first_step')
          expect(first_step[:depends_on_step]).to be_nil
          expect(first_step[:handler_class]).to eq('String')
          expect(first_step[:configuration]).to eq({ timeout: 30 })
          expect(first_step[:dependent_system]).to eq('test_system')

          second_step = serialized_data[:step_templates][1]
          expect(second_step[:name]).to eq('second_step')
          expect(second_step[:depends_on_step]).to eq('first_step')
          expect(second_step[:handler_class]).to eq('String')
          expect(second_step[:configuration]).to eq({ retry_limit: 3 })
          expect(second_step[:dependent_system]).to eq('test_system')
        end
      end

      context 'with string handler class' do
        let(:serializer) do
          described_class.new(
            'TestHandlerClass',
            handler_name: 'test_handler',
            namespace: 'default',
            version: '0.1.0'
          )
        end

        let(:serialized_data) { serializer.serializable_hash }

        it 'handles string class names' do
          expect(serialized_data[:class_name]).to eq('TestHandlerClass')
          expect(serialized_data[:full_name]).to eq('default.test_handler@0.1.0')
        end
      end

      context 'with default namespace and version' do
        let(:serializer) do
          described_class.new(
            test_handler_class,
            handler_name: 'default_handler'
          )
        end

        let(:serialized_data) { serializer.serializable_hash }

        it 'uses default values when not specified' do
          expect(serialized_data[:namespace]).to eq('default')
          expect(serialized_data[:version]).to eq('0.1.0')
          expect(serialized_data[:full_name]).to eq('default.default_handler@0.1.0')
        end
      end

      context 'with minimal handler (no step templates)' do
        let(:serializer) do
          described_class.new(
            minimal_handler_class,
            handler_name: 'minimal_handler',
            namespace: 'simple',
            version: '1.0.0'
          )
        end

        let(:serialized_data) { serializer.serializable_hash }

        it 'handles handlers with empty step templates' do
          expect(serialized_data[:step_templates]).to eq([])
          expect(serialized_data[:available]).to be(true)
        end
      end

      context 'with handler that cannot be instantiated' do
        let(:serializer) do
          described_class.new(
            error_handler_class,
            handler_name: 'error_handler',
            namespace: 'broken',
            version: '1.0.0'
          )
        end

        let(:serialized_data) { serializer.serializable_hash }

        it 'marks handler as unavailable' do
          expect(serialized_data[:available]).to be(false)
          expect(serialized_data[:step_templates]).to eq([])
        end

        it 'does not raise errors during serialization' do
          expect { serialized_data }.not_to raise_error
        end
      end

      context 'with handler that has malformed step templates' do
        let(:malformed_handler_class) do
          Class.new do
            def self.name
              'MalformedHandlerClass'
            end

            def step_templates
              # Return something that will cause an error during processing
              raise StandardError, 'Step template error'
            end
          end
        end

        let(:serializer) do
          described_class.new(
            malformed_handler_class,
            handler_name: 'malformed_handler',
            namespace: 'broken',
            version: '1.0.0'
          )
        end

        it 'handles step template errors gracefully' do
          # Expect Rails.logger to receive a warning
          expect(Rails.logger).to receive(:warn).with(/Failed to introspect step templates/)

          serialized_data = serializer.serializable_hash
          expect(serialized_data[:step_templates]).to eq([])
          expect(serialized_data[:available]).to be(true) # Handler can be instantiated, just templates fail
        end
      end

      context 'with handler that has non-responding step templates' do
        let(:non_responding_handler_class) do
          Class.new do
            def self.name
              'NonRespondingHandlerClass'
            end

            def step_templates
              # Return something that doesn't respond to map
              'not an array'
            end
          end
        end

        let(:serializer) do
          described_class.new(
            non_responding_handler_class,
            handler_name: 'non_responding_handler',
            namespace: 'broken',
            version: '1.0.0'
          )
        end

        it 'handles non-array step templates gracefully' do
          serialized_data = serializer.serializable_hash
          expect(serialized_data[:step_templates]).to eq([])
        end
      end
    end

    describe 'symbol to string conversion' do
      let(:serializer) do
        described_class.new(
          test_handler_class,
          handler_name: :symbol_handler,
          namespace: :symbol_namespace,
          version: :symbol_version
        )
      end

      it 'converts symbols to strings' do
        serialized_data = serializer.serializable_hash
        expect(serialized_data[:name]).to eq('symbol_handler')
        expect(serialized_data[:namespace]).to eq('symbol_namespace')
        expect(serialized_data[:version]).to eq('symbol_version')
      end
    end
  end
end
