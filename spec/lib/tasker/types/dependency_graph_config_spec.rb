# typed: false
# frozen_string_literal: true

require 'rails_helper'

module Tasker
  module Types
    RSpec.describe DependencyGraphConfig, type: :model do
      describe '.new' do
        context 'with default values' do
          subject(:config) { described_class.new }

          it 'sets default impact multipliers' do
            expect(config.impact_multipliers).to eq({
                                                      downstream_weight: 5,
                                                      blocked_weight: 15,
                                                      path_length_weight: 10,
                                                      completed_penalty: 15,
                                                      blocked_penalty: 25,
                                                      error_penalty: 30,
                                                      retry_penalty: 10
                                                    })
          end

          it 'sets default severity multipliers' do
            expect(config.severity_multipliers).to eq({
                                                        error_state: 2.0,
                                                        exhausted_retry_bonus: 0.5,
                                                        dependency_issue: 1.2
                                                      })
          end

          it 'sets default penalty constants' do
            expect(config.penalty_constants).to eq({
                                                     retry_instability: 3,
                                                     non_retryable: 10,
                                                     exhausted_retry: 20
                                                   })
          end

          it 'sets default severity thresholds' do
            expect(config.severity_thresholds).to eq({
                                                       critical: 100,
                                                       high: 50,
                                                       medium: 20
                                                     })
          end

          it 'sets default duration estimates' do
            expect(config.duration_estimates).to eq({
                                                      base_step_seconds: 30,
                                                      error_penalty_seconds: 60,
                                                      retry_penalty_seconds: 30
                                                    })
          end
        end

        context 'with custom values' do
          subject(:config) do
            described_class.new(
              impact_multipliers: {
                downstream_weight: 10,
                blocked_weight: 20
              },
              severity_multipliers: {
                error_state: 3.0
              },
              penalty_constants: {
                retry_instability: 5
              },
              severity_thresholds: {
                critical: 150
              },
              duration_estimates: {
                base_step_seconds: 45
              }
            )
          end

          it 'uses custom impact multipliers and defaults for others' do
            expect(config.impact_multipliers[:downstream_weight]).to eq(10)
            expect(config.impact_multipliers[:blocked_weight]).to eq(20)
            expect(config.impact_multipliers[:path_length_weight]).to eq(10) # default
          end

          it 'uses custom severity multipliers and defaults for others' do
            expect(config.severity_multipliers[:error_state]).to eq(3.0)
            expect(config.severity_multipliers[:exhausted_retry_bonus]).to eq(0.5) # default
          end

          it 'uses custom penalty constants and defaults for others' do
            expect(config.penalty_constants[:retry_instability]).to eq(5)
            expect(config.penalty_constants[:non_retryable]).to eq(10) # default
          end

          it 'uses custom severity thresholds and defaults for others' do
            expect(config.severity_thresholds[:critical]).to eq(150)
            expect(config.severity_thresholds[:high]).to eq(50) # default
          end

          it 'uses custom duration estimates and defaults for others' do
            expect(config.duration_estimates[:base_step_seconds]).to eq(45)
            expect(config.duration_estimates[:error_penalty_seconds]).to eq(60) # default
          end
        end

        context 'with type validation' do
          it 'validates impact multipliers are integers' do
            expect do
              described_class.new(
                impact_multipliers: { downstream_weight: 'invalid' }
              )
            end.to raise_error(Dry::Struct::Error)
          end

          it 'validates severity multipliers are floats' do
            expect do
              described_class.new(
                severity_multipliers: { error_state: 'invalid' }
              )
            end.to raise_error(Dry::Struct::Error)
          end

          it 'validates penalty constants are integers' do
            expect do
              described_class.new(
                penalty_constants: { retry_instability: 'invalid' }
              )
            end.to raise_error(Dry::Struct::Error)
          end

          it 'validates severity thresholds are integers' do
            expect do
              described_class.new(
                severity_thresholds: { critical: 'invalid' }
              )
            end.to raise_error(Dry::Struct::Error)
          end

          it 'validates duration estimates are integers' do
            expect do
              described_class.new(
                duration_estimates: { base_step_seconds: 'invalid' }
              )
            end.to raise_error(Dry::Struct::Error)
          end
        end

        context 'with symbol key transformation' do
          subject(:config) do
            described_class.new(
              'impact_multipliers' => {
                'downstream_weight' => 8,
                'blocked_weight' => 18
              }
            )
          end

          it 'transforms string keys to symbols' do
            expect(config.impact_multipliers[:downstream_weight]).to eq(8)
            expect(config.impact_multipliers[:blocked_weight]).to eq(18)
            expect(config.impact_multipliers[:path_length_weight]).to eq(10) # other values preserved
          end
        end
      end

      describe '#to_h' do
        subject(:config) do
          described_class.new(
            impact_multipliers: { downstream_weight: 7 },
            severity_multipliers: { error_state: 2.5 }
          )
        end

        it 'converts configuration to hash with symbol keys' do
          hash = config.to_h

          expect(hash[:impact_multipliers][:downstream_weight]).to eq(7)
          expect(hash[:severity_multipliers][:error_state]).to eq(2.5)
          expect(hash[:penalty_constants][:retry_instability]).to eq(3) # default
        end
      end
    end
  end
end
