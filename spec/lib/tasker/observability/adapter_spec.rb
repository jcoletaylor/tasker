# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Observability::Adapter do
  # Create a concrete implementation for testing
  class TestAdapter < Tasker::Observability::Adapter
    attr_reader :last_event, :last_payload

    def record(event, payload = {})
      @last_event = event
      @last_payload = payload
    end
  end

  let(:adapter) { TestAdapter.new }

  describe '#record' do
    it 'stores the event and payload' do
      adapter.record('test.event', { test: true })

      expect(adapter.last_event).to eq('test.event')
      expect(adapter.last_payload).to eq({ test: true })
    end
  end

  describe 'optional tracing methods' do
    it 'provides default implementations for tracing methods' do
      # Just testing they don't raise errors, since they're no-ops
      expect { adapter.start_trace('test', {}) }.not_to raise_error
      expect { adapter.end_trace }.not_to raise_error

      result = adapter.add_span('test', {}) { 42 }
      expect(result).to eq(42)
    end
  end

  describe 'subclassing' do
    it 'requires implementing #record' do
      class InvalidAdapter < Tasker::Observability::Adapter; end

      expect { InvalidAdapter.new.record('event') }.to raise_error(NotImplementedError)
    end
  end
end
