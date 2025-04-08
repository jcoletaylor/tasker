# frozen_string_literal: true

require 'rails_helper'
require_relative 'memory_adapter'
require_relative '../../../support/telemetry_test_helper'

RSpec.describe Tasker::Telemetry do
  include TelemetryTestHelper

  let(:memory_adapter) { MemoryAdapter.new }
  let(:event) { 'test.event' }
  let(:payload) { { key: 'value', task_id: 123 } }

  after do
    memory_adapter.clear
  end

  describe '.record' do
    it 'records events in the adapters' do
      with_isolated_telemetry(memory_adapter) do
        described_class.record(event, payload)

        expect(memory_adapter.recorded_events.size).to eq(1)
        expect(memory_adapter.recorded_events.first[:event]).to eq(event)
        expect(memory_adapter.recorded_events.first[:payload]).to eq(payload)
      end
    end
  end

  describe '.start_trace' do
    it 'starts a trace with the given name and attributes' do
      with_isolated_telemetry(memory_adapter) do
        described_class.start_trace('test_trace', payload)

        expect(memory_adapter.traces.size).to eq(1)
        expect(memory_adapter.traces.first[:name]).to eq('test_trace')
        expect(memory_adapter.traces.first[:attributes]).to eq(payload)
      end
    end
  end

  describe '.add_span' do
    it 'creates spans around blocks' do
      with_isolated_telemetry(memory_adapter) do
        result = described_class.add_span('test_span', payload) { 42 }

        expect(result).to eq(42)
        expect(memory_adapter.spans.size).to eq(1)
        expect(memory_adapter.spans.first[:name]).to eq('test_span')
        expect(memory_adapter.spans.first[:attributes]).to eq(payload)
      end
    end
  end
end
