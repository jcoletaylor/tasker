# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::LifecycleEvents do
  let(:event) { 'Test.Event' }
  let(:context) { { key: 'value', task_id: 123 } }
  let(:namespaced_event) { "#{described_class::EVENT_NAMESPACE}.#{event}" }

  let(:captured_events) { [] }
  let(:subscription) { nil }

  before do
    # Create a subscription to capture events
    ActiveSupport::Notifications.subscribe(namespaced_event) do |name, started, finished, id, payload|
      captured_events << {
        name: name,
        started: started,
        finished: finished,
        id: id,
        payload: payload
      }
    end
  end

  after do
    # Clean up subscription
    ActiveSupport::Notifications.unsubscribe(subscription) if subscription
    captured_events.clear
  end

  describe '.fire' do
    it 'instruments the event through ActiveSupport::Notifications' do
      described_class.fire(event, context)

      expect(captured_events.size).to eq(1)
      expect(captured_events.first[:name]).to eq(namespaced_event)
      expect(captured_events.first[:payload]).to eq(context)
    end
  end

  describe '.fire_with_span' do
    it 'instruments the block execution through ActiveSupport::Notifications' do
      result = described_class.fire_with_span(event, context) { 42 }

      expect(result).to eq(42)
      expect(captured_events.size).to eq(1)
      expect(captured_events.first[:name]).to eq(namespaced_event)
      expect(captured_events.first[:payload]).to eq(context)
    end

    it 'correctly captures the execution time of the block' do
      # Make the block take a measurable amount of time
      described_class.fire_with_span(event, context) { sleep(0.01) }

      expect(captured_events.first[:finished] - captured_events.first[:started]).to be > 0.005
    end
  end

  describe '.fire_error' do
    it 'instruments the error event with exception information' do
      exception = StandardError.new('Test error')
      exception.set_backtrace(%w[line1 line2])

      described_class.fire_error(event, exception, context)

      expect(captured_events.size).to eq(1)
      expect(captured_events.first[:name]).to eq(namespaced_event)
      expect(captured_events.first[:payload][:key]).to eq('value')
      expect(captured_events.first[:payload][:exception]).to eq([exception.class.name, exception.message])
      expect(captured_events.first[:payload][:exception_object]).to eq(exception)
      expect(captured_events.first[:payload][:backtrace]).to include('line1')
    end
  end
end
