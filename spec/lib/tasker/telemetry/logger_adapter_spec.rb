# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Telemetry::LoggerAdapter do
  let(:log_output) { StringIO.new }
  let(:test_logger) { Logger.new(log_output) }
  let(:adapter) { described_class.new }
  let(:event) { 'test.event' }
  let(:payload) { { key: 'value', task_id: 123 } }

  before do
    allow(Rails).to receive(:logger).and_return(test_logger)
  end

  describe '#record' do
    it 'logs the event and payload as JSON' do
      adapter.record(event, payload)

      # Verify something was logged
      expect(log_output.string).not_to be_empty

      # Verify it contains our event and payload data
      expect(log_output.string).to include(event)
      expect(log_output.string).to include('"key":"value"')
      expect(log_output.string).to include('"task_id":123')
    end
  end

  describe 'tracing methods' do
    it 'provides no-op implementations for tracing' do
      # Just verify they don't raise errors
      expect { adapter.start_trace('test', {}) }.not_to raise_error
      expect { adapter.end_trace }.not_to raise_error

      result = nil
      expect { result = adapter.add_span('test', {}) { 42 } }.not_to raise_error
      expect(result).to eq(42)
    end
  end
end
