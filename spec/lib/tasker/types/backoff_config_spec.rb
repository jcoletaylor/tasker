# typed: false
# frozen_string_literal: true

require 'rails_helper'

module Tasker
  module Types
    RSpec.describe BackoffConfig, type: :model do
      describe '.new' do
        context 'with default values' do
          subject(:config) { described_class.new }

          it 'sets default backoff progression' do
            expect(config.default_backoff_seconds).to eq([1, 2, 4, 8, 16, 32])
          end

          it 'sets default max backoff seconds' do
            expect(config.max_backoff_seconds).to eq(300)
          end

          it 'sets default backoff multiplier' do
            expect(config.backoff_multiplier).to eq(2.0)
          end

          it 'sets default jitter enabled' do
            expect(config.jitter_enabled).to be true
          end

          it 'sets default jitter max percentage' do
            expect(config.jitter_max_percentage).to eq(0.1)
          end
        end

        context 'with custom values' do
          subject(:config) do
            described_class.new(
              default_backoff_seconds: [1, 3, 9, 27],
              max_backoff_seconds: 600,
              backoff_multiplier: 3.0,
              jitter_enabled: false,
              jitter_max_percentage: 0.2
            )
          end

          it 'uses custom default backoff progression' do
            expect(config.default_backoff_seconds).to eq([1, 3, 9, 27])
          end

          it 'uses custom max backoff seconds' do
            expect(config.max_backoff_seconds).to eq(600)
          end

          it 'uses custom backoff multiplier' do
            expect(config.backoff_multiplier).to eq(3.0)
          end

          it 'uses custom jitter enabled setting' do
            expect(config.jitter_enabled).to be false
          end

          it 'uses custom jitter max percentage' do
            expect(config.jitter_max_percentage).to eq(0.2)
          end
        end

        context 'with string keys' do
          subject(:config) do
            described_class.new(
              'max_backoff_seconds' => 120,
              'jitter_enabled' => false
            )
          end

          it 'transforms string keys to symbols' do
            expect(config.max_backoff_seconds).to eq(120)
            expect(config.jitter_enabled).to be false
          end
        end
      end

      describe 'type validation' do
        context 'with invalid default_backoff_seconds' do
          it 'raises an error for non-array value' do
            expect do
              described_class.new(default_backoff_seconds: 'invalid')
            end.to raise_error(Dry::Struct::Error)
          end

          it 'raises an error for non-integer array elements' do
            expect do
              described_class.new(default_backoff_seconds: [1, 'invalid', 3])
            end.to raise_error(Dry::Struct::Error)
          end
        end

        context 'with invalid max_backoff_seconds' do
          it 'raises an error for non-integer value' do
            expect do
              described_class.new(max_backoff_seconds: 'invalid')
            end.to raise_error(Dry::Struct::Error)
          end
        end

        context 'with invalid backoff_multiplier' do
          it 'raises an error for non-numeric value' do
            expect do
              described_class.new(backoff_multiplier: 'invalid')
            end.to raise_error(Dry::Struct::Error)
          end
        end

        context 'with invalid jitter_enabled' do
          it 'raises an error for non-boolean value' do
            expect do
              described_class.new(jitter_enabled: 'invalid')
            end.to raise_error(Dry::Struct::Error)
          end
        end

        context 'with invalid jitter_max_percentage' do
          it 'raises an error for non-numeric value' do
            expect do
              described_class.new(jitter_max_percentage: 'invalid')
            end.to raise_error(Dry::Struct::Error)
          end
        end
      end

      describe '#calculate_backoff_seconds' do
        context 'with default configuration' do
          subject(:config) { described_class.new }

          context 'with invalid attempt numbers' do
            it 'returns 0 for zero attempt' do
              expect(config.calculate_backoff_seconds(0)).to eq(0)
            end

            it 'returns 0 for negative attempt' do
              expect(config.calculate_backoff_seconds(-1)).to eq(0)
            end
          end

          context 'with attempts within default progression' do
            let(:config_no_jitter) { described_class.new(jitter_enabled: false) }

            it 'returns correct backoff for first attempt' do
              expect(config_no_jitter.calculate_backoff_seconds(1)).to eq(1)
            end

            it 'returns correct backoff for third attempt' do
              expect(config_no_jitter.calculate_backoff_seconds(3)).to eq(4)
            end

            it 'returns correct backoff for last predefined attempt' do
              expect(config_no_jitter.calculate_backoff_seconds(6)).to eq(32)
            end
          end

          context 'with attempts beyond default progression' do
            let(:config_no_jitter) do
              described_class.new(jitter_enabled: false)
            end

            it 'uses exponential backoff calculation' do
              # Attempt 7: 7^2 = 49 seconds
              expect(config_no_jitter.calculate_backoff_seconds(7)).to eq(49)
            end

            it 'caps at max_backoff_seconds' do
              # Large attempt should be capped at 300 seconds
              expect(config_no_jitter.calculate_backoff_seconds(100)).to eq(300)
            end
          end
        end

        context 'with custom configuration' do
          subject(:config) do
            described_class.new(
              default_backoff_seconds: [5, 10],
              max_backoff_seconds: 60,
              backoff_multiplier: 1.5,
              jitter_enabled: false
            )
          end

          it 'uses custom progression for early attempts' do
            expect(config.calculate_backoff_seconds(1)).to eq(5)
            expect(config.calculate_backoff_seconds(2)).to eq(10)
          end

          it 'uses custom multiplier for exponential calculation' do
            # Attempt 3: 3^1.5 ≈ 5.196... rounded to 5
            expect(config.calculate_backoff_seconds(3)).to eq(5)
          end

          it 'uses custom max backoff limit' do
            # Large attempt should be capped at custom limit
            expect(config.calculate_backoff_seconds(100)).to eq(60)
          end
        end

        context 'with jitter enabled' do
          subject(:config) do
            described_class.new(
              jitter_enabled: true,
              jitter_max_percentage: 0.5 # 50% jitter for easier testing
            )
          end

          it 'applies jitter to backoff calculation' do
            # With 50% jitter on first attempt (1 second), result should be 0-2 seconds
            # but minimum 1 second due to the constraint
            results = 10.times.map { config.calculate_backoff_seconds(1) } # rubocop:disable Performance/TimesMap
            expect(results).to all(be >= 1)
            expect(results).to all(be <= 2)
          end

          it 'ensures minimum 1 second backoff even with negative jitter' do
            # Even with maximum negative jitter, should never go below 1
            results = 100.times.map { config.calculate_backoff_seconds(1) } # rubocop:disable Performance/TimesMap
            expect(results).to all(be >= 1)
          end
        end

        context 'with jitter disabled' do
          subject(:config) do
            described_class.new(jitter_enabled: false)
          end

          it 'returns consistent results without jitter' do
            results = 10.times.map { config.calculate_backoff_seconds(1) } # rubocop:disable Performance/TimesMap
            expect(results.uniq).to eq([1])
          end
        end
      end

      describe 'immutability' do
        subject(:config) { described_class.new }

        it 'creates frozen objects' do
          expect(config).to be_frozen
        end

        it 'creates frozen arrays' do
          expect(config.default_backoff_seconds).to be_frozen
        end
      end

      describe 'equality' do
        let(:config1) { described_class.new }
        let(:config2) { described_class.new }
        let(:config3) { described_class.new(max_backoff_seconds: 600) }

        it 'equals other configs with same values' do
          expect(config1).to eq(config2)
        end

        it 'does not equal configs with different values' do
          expect(config1).not_to eq(config3)
        end
      end

      describe '#to_h' do
        subject(:config) do
          described_class.new(max_backoff_seconds: 120)
        end

        it 'returns a hash representation' do
          hash = config.to_h
          expect(hash).to be_a(::Hash)
          expect(hash[:max_backoff_seconds]).to eq(120)
        end
      end
    end
  end
end
