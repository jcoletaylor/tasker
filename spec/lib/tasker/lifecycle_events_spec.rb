# frozen_string_literal: true

require 'rails_helper'

class TestObserver
  attr_reader :events, :spans

  def initialize
    @events = []
    @spans = []
  end

  def on_lifecycle_event(event, context)
    @events << { event: event, context: context }
  end

  def trace_execution(name, context, &)
    proc do
      @spans << { name: name, context: context, started_at: Time.current }
      result = yield if block_given?
      @spans.last[:ended_at] = Time.current
      result
    end
  end

  def clear
    @events = []
    @spans = []
  end
end

RSpec.describe Tasker::LifecycleEvents do
  # Create a real observer that collects events

  let(:observer) { TestObserver.new }
  let(:event) { 'test.event' }
  let(:context) { { key: 'value', task_id: 123 } }

  before do
    described_class.reset_observers
    described_class.register_observer(observer)
  end

  after do
    observer.clear
  end

  describe '.fire' do
    it 'notifies registered observers' do
      described_class.fire(event, context)

      expect(observer.events.size).to eq(1)
      expect(observer.events.first[:event]).to eq(event)
      expect(observer.events.first[:context]).to eq(context)
    end
  end

  describe '.fire_with_span' do
    it 'creates a span and executes the block' do
      result = described_class.fire_with_span(event, context) { 42 }

      expect(result).to eq(42)
      expect(observer.events.size).to eq(1)
      expect(observer.spans.size).to eq(1)
      expect(observer.spans.first[:name]).to eq(event)
    end
  end
end
