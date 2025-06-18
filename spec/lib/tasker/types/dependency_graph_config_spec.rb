# typed: false
# frozen_string_literal: true

require 'rails_helper'

module Tasker
  module Types
    RSpec.describe DependencyGraphConfig, type: :model do
      describe '.new' do
        context 'with default values' do
          subject(:config) { described_class.new }

          it 'sets default weight multipliers' do
            expect(config.weight_multipliers).to eq({
                                                      complexity: 1.5,
                                                      priority: 2.0,
                                                      depth: 1.2,
                                                      fan_out: 0.8
                                                    })
          end

          it 'sets default threshold constants' do
            expect(config.threshold_constants).to eq({
                                                       bottleneck_threshold: 0.8,
                                                       critical_path_threshold: 0.9,
                                                       warning_threshold: 0.6
                                                     })
          end

          it 'sets default calculation limits' do
            expect(config.calculation_limits).to eq({
                                                      max_depth: 50,
                                                      max_nodes: 1000,
                                                      timeout_seconds: 30
                                                    })
          end
        end

        context 'with custom values' do
          let(:custom_weight_multipliers) do
            {
              complexity: 2.0,
              priority: 1.5,
              depth: 1.0,
              fan_out: 1.2
            }
          end

          let(:custom_threshold_constants) do
            {
              bottleneck_threshold: 0.7,
              critical_path_threshold: 0.95,
              warning_threshold: 0.5
            }
          end

          let(:custom_calculation_limits) do
            {
              max_depth: 100,
              max_nodes: 2000,
              timeout_seconds: 60
            }
          end

          subject(:config) do
            described_class.new(
              weight_multipliers: custom_weight_multipliers,
              threshold_constants: custom_threshold_constants,
              calculation_limits: custom_calculation_limits
            )
          end

          it 'uses custom weight multipliers' do
            expect(config.weight_multipliers).to eq(custom_weight_multipliers)
          end

          it 'uses custom threshold constants' do
            expect(config.threshold_constants).to eq(custom_threshold_constants)
          end

          it 'uses custom calculation limits' do
            expect(config.calculation_limits).to eq(custom_calculation_limits)
          end
        end

        context 'with partial custom values' do
          subject(:config) do
            described_class.new(
              weight_multipliers: { complexity: 3.0 }
            )
          end

          it 'merges custom values with defaults' do
            expect(config.weight_multipliers).to eq({
                                                      complexity: 3.0,
                                                      priority: 2.0,
                                                      depth: 1.2,
                                                      fan_out: 0.8
                                                    })
          end

          it 'keeps default threshold constants' do
            expect(config.threshold_constants).to eq({
                                                       bottleneck_threshold: 0.8,
                                                       critical_path_threshold: 0.9,
                                                       warning_threshold: 0.6
                                                     })
          end
        end


      end

      describe 'type validation' do
        context 'with invalid weight multiplier types' do
          it 'raises an error for non-numeric complexity' do
            expect do
              described_class.new(
                weight_multipliers: { complexity: 'invalid' }
              )
            end.to raise_error(Dry::Struct::Error)
          end
        end

        context 'with invalid threshold constant types' do
          it 'raises an error for non-numeric threshold' do
            expect do
              described_class.new(
                threshold_constants: { bottleneck_threshold: 'invalid' }
              )
            end.to raise_error(Dry::Struct::Error)
          end
        end

        context 'with invalid calculation limit types' do
          it 'raises an error for non-integer max_depth' do
            expect do
              described_class.new(
                calculation_limits: { max_depth: 'invalid' }
              )
            end.to raise_error(Dry::Struct::Error)
          end
        end
      end

      describe 'immutability' do
        subject(:config) { described_class.new }

        it 'creates frozen objects' do
          expect(config).to be_frozen
        end

        it 'creates frozen nested hashes' do
          expect(config.weight_multipliers).to be_frozen
          expect(config.threshold_constants).to be_frozen
          expect(config.calculation_limits).to be_frozen
        end
      end

      describe 'equality' do
        let(:config1) { described_class.new }
        let(:config2) { described_class.new }
        let(:config3) { described_class.new(weight_multipliers: { complexity: 3.0 }) }

        it 'equals other configs with same values' do
          expect(config1).to eq(config2)
        end

        it 'does not equal configs with different values' do
          expect(config1).not_to eq(config3)
        end
      end

      describe '#to_h' do
        subject(:config) do
          described_class.new(
            weight_multipliers: { complexity: 2.0 }
          )
        end

        it 'returns a hash representation' do
          hash = config.to_h
          expect(hash).to be_a(::Hash)
          expect(hash[:weight_multipliers][:complexity]).to eq(2.0)
        end
      end
    end
  end
end
