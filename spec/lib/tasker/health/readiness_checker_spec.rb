# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Health::ReadinessChecker, type: :model do
  describe '.ready?' do
    context 'when all systems are healthy' do
      before do
        # Mock healthy database connection
        allow(ActiveRecord::Base.connection).to receive(:execute).and_return([{ 'result' => '1' }])
        # Mock healthy cache operations - simulate successful write/read/delete cycle
        cache_store = {}
        allow(Rails.cache).to receive(:write) { |key, value, _options|
          cache_store[key] = value
          true
        }
        allow(Rails.cache).to receive(:read) { |key| cache_store[key] }
        allow(Rails.cache).to receive(:delete) { |key|
          cache_store.delete(key)
          true
        }
      end

      it 'returns true' do
        expect(described_class.ready?).to be true
      end
    end

    context 'when database is unavailable' do
      before do
        allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(ActiveRecord::ConnectionNotEstablished)
      end

      it 'returns false' do
        expect(described_class.ready?).to be false
      end
    end

    context 'when database query times out' do
      before do
        allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(ActiveRecord::StatementTimeout)
      end

      it 'returns false' do
        expect(described_class.ready?).to be false
      end
    end

    context 'when cache is unavailable' do
      before do
        allow(ActiveRecord::Base.connection).to receive(:execute).and_return([{ 'result' => '1' }])
        # Use a generic error instead of Redis-specific error
        allow(Rails.cache).to receive(:write).and_raise(StandardError.new('Cache unavailable'))
      end

      it 'returns false' do
        expect(described_class.ready?).to be false
      end
    end
  end

  describe '.detailed_status' do
    context 'when all systems are healthy' do
      before do
        allow(ActiveRecord::Base.connection).to receive(:execute).and_return([{ 'result' => '1' }])
        # Mock healthy cache operations - simulate successful write/read/delete cycle
        cache_store = {}
        allow(Rails.cache).to receive(:write) { |key, value, _options|
          cache_store[key] = value
          true
        }
        allow(Rails.cache).to receive(:read) { |key| cache_store[key] }
        allow(Rails.cache).to receive(:delete) { |key|
          cache_store.delete(key)
          true
        }
      end

      it 'returns detailed success status' do
        result = described_class.detailed_status

        expect(result[:ready]).to be true
        expect(result[:checks]).to have_key(:database)
        expect(result[:checks]).to have_key(:cache)
        expect(result[:checks][:database][:status]).to eq('healthy')
        expect(result[:checks][:cache][:status]).to eq('healthy')
        expect(result[:timestamp]).to be_within(1.second).of(Time.current)
      end
    end

    context 'when database fails' do
      before do
        allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(ActiveRecord::ConnectionNotEstablished.new('Connection failed'))
        # Mock healthy cache operations - simulate successful write/read/delete cycle
        cache_store = {}
        allow(Rails.cache).to receive(:write) { |key, value, _options|
          cache_store[key] = value
          true
        }
        allow(Rails.cache).to receive(:read) { |key| cache_store[key] }
        allow(Rails.cache).to receive(:delete) { |key|
          cache_store.delete(key)
          true
        }
      end

      it 'returns detailed failure status' do
        result = described_class.detailed_status

        expect(result[:ready]).to be false
        expect(result[:checks][:database][:status]).to eq('unhealthy')
        expect(result[:checks][:database][:error]).to include('Connection failed')
        expect(result[:checks][:cache][:status]).to eq('healthy')
        expect(result[:failed_checks]).to include('database')
      end
    end

    context 'when cache fails' do
      before do
        allow(ActiveRecord::Base.connection).to receive(:execute).and_return([{ 'result' => '1' }])
        allow(Rails.cache).to receive(:write).and_raise(StandardError.new('Cache unavailable'))
      end

      it 'returns detailed failure status' do
        result = described_class.detailed_status

        expect(result[:ready]).to be false
        expect(result[:checks][:database][:status]).to eq('healthy')
        expect(result[:checks][:cache][:status]).to eq('unhealthy')
        expect(result[:checks][:cache][:error]).to include('StandardError')
        expect(result[:failed_checks]).to include('cache')
      end
    end

    context 'when multiple systems fail' do
      before do
        allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(ActiveRecord::ConnectionNotEstablished.new('DB down'))
        allow(Rails.cache).to receive(:write).and_raise(StandardError.new('Cache down'))
      end

      it 'returns status with all failures' do
        result = described_class.detailed_status

        expect(result[:ready]).to be false
        expect(result[:checks][:database][:status]).to eq('unhealthy')
        expect(result[:checks][:cache][:status]).to eq('unhealthy')
        expect(result[:failed_checks]).to contain_exactly('database', 'cache')
        expect(result[:checks][:database][:error]).to include('DB down')
        expect(result[:checks][:cache][:error]).to include('Cache down')
      end
    end
  end

  describe 'timeout protection' do
    it 'handles database timeouts gracefully' do
      allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(ActiveRecord::StatementTimeout)

      result = described_class.detailed_status
      expect(result[:ready]).to be false
      expect(result[:checks][:database][:status]).to eq('unhealthy')
      expect(result[:checks][:database][:error]).to include('StatementTimeout')
    end

    it 'handles cache timeouts gracefully' do
      allow(ActiveRecord::Base.connection).to receive(:execute).and_return([{ 'result' => '1' }])
      allow(Rails.cache).to receive(:write).and_raise(Timeout::Error)

      result = described_class.detailed_status
      expect(result[:ready]).to be false
      expect(result[:checks][:cache][:status]).to eq('unhealthy')
      expect(result[:checks][:cache][:error]).to include('Timeout::Error')
    end
  end

  describe 'response time tracking' do
    it 'includes response times in detailed status' do
      allow(ActiveRecord::Base.connection).to receive(:execute).and_return([{ 'result' => '1' }])
      # Mock healthy cache operations - simulate successful write/read/delete cycle
      cache_store = {}
      allow(Rails.cache).to receive(:write) { |key, value, _options|
        cache_store[key] = value
        true
      }
      allow(Rails.cache).to receive(:read) { |key| cache_store[key] }
      allow(Rails.cache).to receive(:delete) { |key|
        cache_store.delete(key)
        true
      }

      result = described_class.detailed_status

      expect(result[:checks][:database]).to have_key(:response_time_ms)
      expect(result[:checks][:cache]).to have_key(:response_time_ms)
      expect(result[:checks][:database][:response_time_ms]).to be >= 0
      expect(result[:checks][:cache][:response_time_ms]).to be >= 0
    end

    it 'tracks response times even for failures' do
      allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(ActiveRecord::ConnectionNotEstablished)
      # Mock healthy cache operations - simulate successful write/read/delete cycle
      cache_store = {}
      allow(Rails.cache).to receive(:write) { |key, value, _options|
        cache_store[key] = value
        true
      }
      allow(Rails.cache).to receive(:read) { |key| cache_store[key] }
      allow(Rails.cache).to receive(:delete) { |key|
        cache_store.delete(key)
        true
      }

      result = described_class.detailed_status

      expect(result[:checks][:database]).to have_key(:response_time_ms)
      expect(result[:checks][:cache]).to have_key(:response_time_ms)
      expect(result[:checks][:database][:response_time_ms]).to be >= 0
    end
  end

  describe 'integration with real systems' do
    it 'works with actual database connection' do
      # This test uses the real database connection
      result = described_class.detailed_status

      expect(result).to have_key(:ready)
      expect(result).to have_key(:checks)
      expect(result).to have_key(:timestamp)
      expect(result[:checks][:database]).to have_key(:status)
    end

    it 'works with actual cache system' do
      # This test uses the real cache system
      result = described_class.detailed_status

      expect(result[:checks][:cache]).to have_key(:status)
      # Cache might be healthy or unhealthy depending on test environment
      expect(%w[healthy unhealthy]).to include(result[:checks][:cache][:status])
    end
  end
end
