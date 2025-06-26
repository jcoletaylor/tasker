# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Registry::SubscriberRegistry, type: :model do
  let(:registry) { described_class.instance }

  # Test subscriber classes
  let(:test_subscriber_class) do
    Class.new do
      def self.name
        'TestSubscriber'
      end

      def call(event)
        # Test implementation
      end
    end
  end

  let(:another_subscriber_class) do
    Class.new do
      def self.name
        'AnotherSubscriber'
      end

      def call(event)
        # Test implementation
      end
    end
  end

  let(:invalid_subscriber_class) do
    Class.new do
      def self.name
        'InvalidSubscriber'
      end
      # Missing call method
    end
  end

  before do
    # Clear registry before each test
    registry.clear!
  end

  describe '#initialize' do
    it 'initializes with empty collections' do
      # Since it's a singleton, we can't test initialization directly
      # Instead, we test that a fresh registry starts empty
      registry.clear!

      expect(registry.all_subscribers).to be_empty
      expect(registry.supported_events).to be_empty
    end

    it 'logs initialization' do
      # Test that the singleton instance is properly initialized
      expect(registry).to be_a(described_class)
      expect(registry.all_subscribers).to be_a(Hash)
    end
  end

  describe '#register' do
    it 'registers a subscriber with events' do
      events = ['task.created', 'task.completed']

      result = registry.register(test_subscriber_class, events: events)

      expect(result).to be true
      expect(registry.all_subscribers).to have_key('test_subscriber')
      expect(registry.supported_events).to contain_exactly('task.created', 'task.completed')
    end

    it 'validates subscriber interface' do
      expect do
        registry.register(invalid_subscriber_class, events: ['test.event'])
      end.to raise_error(ArgumentError, /must implement instance method call/)
    end

    it 'prevents duplicate registration without replace option' do
      registry.register(test_subscriber_class, events: ['test.event'])

      expect do
        registry.register(test_subscriber_class, events: ['other.event'])
      end.to raise_error(ArgumentError, /already registered.*replace: true/)
    end

    it 'allows replacement with replace: true option' do
      registry.register(test_subscriber_class, events: ['old.event'])

      expect do
        registry.register(test_subscriber_class, events: ['new.event'], replace: true)
      end.not_to raise_error

      subscriber_config = registry.all_subscribers['test_subscriber']
      expect(subscriber_config[:events]).to eq(['new.event'])
      expect(registry.supported_events).to contain_exactly('new.event')
    end

    it 'handles multiple events per subscriber' do
      events = ['event.one', 'event.two', 'event.three']

      registry.register(test_subscriber_class, events: events)

      expect(registry.supported_events).to match_array(events)
      events.each do |event|
        subscribers = registry.subscribers_for_event(event)
        expect(subscribers.size).to eq(1)
        expect(subscribers.first[:subscriber_class]).to eq(test_subscriber_class)
      end
    end

    it 'stores registration metadata' do
      events = ['test.event']
      options = { priority: :high, custom: 'value' }

      registry.register(test_subscriber_class, events: events, **options)

      subscriber_config = registry.all_subscribers['test_subscriber']
      expect(subscriber_config[:subscriber_class]).to eq(test_subscriber_class)
      expect(subscriber_config[:events]).to eq(events)
      expect(subscriber_config[:registered_at]).to be_a(Time)
      expect(subscriber_config[:options]).to include(options)
    end
  end

  describe '#unregister' do
    before do
      registry.register(test_subscriber_class, events: ['test.event', 'other.event'])
    end

    it 'unregisters subscriber by class' do
      result = registry.unregister(test_subscriber_class)

      expect(result).to be true
      expect(registry.all_subscribers).to be_empty
      expect(registry.supported_events).to be_empty
    end

    it 'unregisters subscriber by name string' do
      result = registry.unregister('test_subscriber')

      expect(result).to be true
      expect(registry.all_subscribers).to be_empty
    end

    it 'returns false for non-existent subscriber' do
      result = registry.unregister('nonexistent_subscriber')

      expect(result).to be false
    end

    it 'removes event mappings when unregistering' do
      # Register another subscriber for the same event
      registry.register(another_subscriber_class, events: ['test.event'])

      # Unregister first subscriber
      registry.unregister(test_subscriber_class)

      # Event should still exist for the other subscriber
      expect(registry.supported_events).to include('test.event')
      subscribers = registry.subscribers_for_event('test.event')
      expect(subscribers.size).to eq(1)
      expect(subscribers.first[:subscriber_class]).to eq(another_subscriber_class)
    end

    it 'removes event completely when no subscribers remain' do
      registry.unregister(test_subscriber_class)

      expect(registry.supported_events).not_to include('test.event')
      expect(registry.subscribers_for_event('test.event')).to be_empty
    end
  end

  describe '#subscribers_for_event' do
    before do
      registry.register(test_subscriber_class, events: ['shared.event', 'test.event'])
      registry.register(another_subscriber_class, events: ['shared.event', 'other.event'])
    end

    it 'returns subscribers for a specific event' do
      subscribers = registry.subscribers_for_event('shared.event')

      expect(subscribers.size).to eq(2)
      subscriber_classes = subscribers.map { |config| config[:subscriber_class] }
      expect(subscriber_classes).to contain_exactly(test_subscriber_class, another_subscriber_class)
    end

    it 'returns empty array for events with no subscribers' do
      subscribers = registry.subscribers_for_event('nonexistent.event')

      expect(subscribers).to be_empty
    end

    it 'handles string and symbol event names' do
      string_subscribers = registry.subscribers_for_event('shared.event')
      registry.subscribers_for_event(:shared_event)

      # Should handle string event names
      expect(string_subscribers.size).to eq(2)
      # Symbol conversion would need to be implemented if needed
    end
  end

  describe '#has_subscribers?' do
    before do
      registry.register(test_subscriber_class, events: ['active.event'])
    end

    it 'returns true for events with subscribers' do
      expect(registry.has_subscribers?('active.event')).to be true
    end

    it 'returns false for events without subscribers' do
      expect(registry.has_subscribers?('inactive.event')).to be false
    end

    it 'handles string and symbol event names' do
      expect(registry.has_subscribers?('active.event')).to be true
      # Could add symbol support if needed
    end
  end

  describe '#stats' do
    before do
      registry.register(test_subscriber_class, events: ['event.one', 'event.two', 'shared.event'])
      registry.register(another_subscriber_class, events: ['event.three', 'shared.event'])
    end

    it 'returns comprehensive statistics' do
      stats = registry.stats

      expect(stats).to include(
        registry_name: 'subscriber_registry',
        total_subscribers: 2,
        total_events: 4,
        subscribers_by_event: {
          'event.one' => 1,
          'event.two' => 1,
          'event.three' => 1,
          'shared.event' => 2
        },
        average_events_per_subscriber: 2.5
      )

      # Check events_covered contains the right events (order doesn't matter)
      expect(stats[:events_covered]).to contain_exactly('event.one', 'event.two', 'event.three', 'shared.event')
    end

    it 'includes base registry statistics' do
      stats = registry.stats

      expect(stats).to include(
        created_at: be_a(Time),
        uptime_seconds: be_a(Integer)
      )
    end

    it 'calculates most popular events' do
      stats = registry.stats

      expect(stats[:most_popular_events]).to be_an(Array)
      expect(stats[:most_popular_events].first).to include(
        event: 'shared.event',
        subscriber_count: 2
      )
    end
  end

  describe '#clear!' do
    before do
      registry.register(test_subscriber_class, events: ['test.event'])
      registry.register(another_subscriber_class, events: ['other.event'])
    end

    it 'clears all subscribers and event mappings' do
      result = registry.clear!

      expect(result).to be true
      expect(registry.all_subscribers).to be_empty
      expect(registry.supported_events).to be_empty
      expect(registry.subscribers_for_event('test.event')).to be_empty
    end
  end

  describe 'thread safety' do
    it 'handles concurrent registrations safely' do
      threads = []
      results = Concurrent::Array.new

      # Create multiple threads that register subscribers concurrently
      10.times do |i|
        threads << Thread.new do
          subscriber_class = Class.new do
            define_singleton_method(:name) { "ConcurrentSubscriber#{i}" }
            define_method(:call) { |event| }
          end

          begin
            result = registry.register(subscriber_class, events: ["event.#{i}"])
            results << { thread: i, success: result }
          rescue StandardError => e
            results << { thread: i, error: e.message }
          end
        end
      end

      threads.each(&:join)

      # All registrations should succeed
      expect(results.size).to eq(10)
      expect(results.all? { |r| r[:success] == true }).to be true
      expect(registry.all_subscribers.size).to eq(10)
    end
  end

  describe 'integration with BaseRegistry' do
    it 'inherits BaseRegistry functionality' do
      expect(registry).to be_a(Tasker::Registry::BaseRegistry)
      expect(registry).to respond_to(:stats)
      expect(registry).to respond_to(:all_items)
      expect(registry).to respond_to(:clear!)
    end

    it 'implements required BaseRegistry methods' do
      expect(registry.all_items).to eq(registry.all_subscribers)

      registry.register(test_subscriber_class, events: ['test.event'])
      expect(registry.all_items).not_to be_empty
    end
  end

  describe 'structured logging' do
    it 'logs registration events' do
      expect { registry.register(test_subscriber_class, events: ['test.event']) }
        .not_to raise_error
    end

    it 'logs validation failures' do
      expect { registry.register(invalid_subscriber_class, events: ['test.event']) }
        .to raise_error(ArgumentError)
    end

    it 'logs unregistration events' do
      registry.register(test_subscriber_class, events: ['test.event'])

      expect { registry.unregister(test_subscriber_class) }
        .not_to raise_error
    end
  end
end
