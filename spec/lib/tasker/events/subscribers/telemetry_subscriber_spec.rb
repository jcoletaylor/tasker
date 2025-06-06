# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Events::Subscribers::TelemetrySubscriber do
  let(:publisher) { Tasker::Events::Publisher.instance }
  let(:subscriber) { described_class.new }

  describe 'subscription setup' do
    it 'subscribes to all expected event types' do
      expected_events = [
        Tasker::Constants::TaskEvents::INITIALIZE_REQUESTED,
        Tasker::Constants::TaskEvents::START_REQUESTED,
        Tasker::Constants::TaskEvents::COMPLETED,
        Tasker::Constants::TaskEvents::FAILED,
        Tasker::Constants::StepEvents::EXECUTION_REQUESTED,
        Tasker::Constants::StepEvents::COMPLETED,
        Tasker::Constants::StepEvents::FAILED,
        Tasker::Constants::StepEvents::RETRY_REQUESTED
      ]

      expect(described_class.subscribed_events).to match_array(expected_events)
    end
  end

  describe 'event handling without OpenTelemetry' do
    before do
      # Stub OpenTelemetry availability check to return false
      allow(subscriber).to receive(:opentelemetry_available?).and_return(false)
    end

    describe '#handle_task_start_requested' do
      it 'processes task start events gracefully without OpenTelemetry' do
        event = { task_id: 'task-123', task_name: 'test_task' }

        # Should not raise error and handle gracefully
        expect { subscriber.handle_task_start_requested(event) }.not_to raise_error
      end
    end

    describe '#handle_task_completed' do
      it 'processes task completion events gracefully without OpenTelemetry' do
        event = { task_id: 'task-123', task_name: 'test_task', total_steps: 5 }

        # Should not raise error and handle gracefully
        expect { subscriber.handle_task_completed(event) }.not_to raise_error
      end
    end

    describe '#handle_step_completed' do
      it 'processes step completion events gracefully without OpenTelemetry' do
        event = { task_id: 'task-123', step_id: 'step-456', step_name: 'test_step', execution_duration: 1.23 }

        # Should not raise error and handle gracefully
        expect { subscriber.handle_step_completed(event) }.not_to raise_error
      end
    end
  end

  describe 'OpenTelemetry span creation', if: defined?(OpenTelemetry) do
    let(:mock_tracer) { instance_double(OpenTelemetry::Trace::Tracer) }
    let(:mock_span) do
      instance_double(OpenTelemetry::Trace::Span,
                      add_event: nil,
                      finish: nil).tap do |span|
        allow(span).to receive(:status=)
      end
    end
    let(:mock_span_context) { instance_double(OpenTelemetry::Trace::SpanContext) }

    before do
      # Mock OpenTelemetry components
      allow(OpenTelemetry).to receive(:tracer_provider)
        .and_return(instance_double(OpenTelemetry::SDK::Trace::TracerProvider, tracer: mock_tracer))
      allow(mock_tracer).to receive(:start_root_span).and_return(mock_span)
      allow(mock_tracer).to receive(:in_span).and_yield(mock_span)
      allow(OpenTelemetry::Trace).to receive(:context_with_span).and_return(mock_span_context)
      allow(OpenTelemetry::Context).to receive(:with_current).and_yield

      # Ensure subscriber thinks OpenTelemetry is available
      allow(subscriber).to receive(:opentelemetry_available?).and_return(true)
    end

    describe 'task span lifecycle' do
      it 'creates a root span for task start events' do
        event = { task_id: 'task-123', task_name: 'test_task' }

        expect(mock_tracer).to receive(:start_root_span)
          .with('tasker.task.execution', hash_including(:attributes))
          .and_return(mock_span)

        expect(mock_span).to receive(:add_event)
          .with('task.started', anything)

        subscriber.handle_task_start_requested(event)

        # Verify span is stored for later use
        expect(subscriber.send(:get_task_span, 'task-123')).to eq(mock_span)
      end

      it 'finishes the task span on completion with success status' do
        # First create a task span
        event = { task_id: 'task-123', task_name: 'test_task' }
        subscriber.handle_task_start_requested(event)

        completion_event = { task_id: 'task-123', task_name: 'test_task', total_steps: 3 }

        expect(mock_span).to receive(:add_event)
          .with('task.completed', anything)

        expect(mock_span).to receive(:finish)

        subscriber.handle_task_completed(completion_event)

        # Verify span is removed after completion
        expect(subscriber.send(:get_task_span, 'task-123')).to be_nil
      end

      it 'finishes the task span on failure with error status' do
        # First create a task span
        event = { task_id: 'task-123', task_name: 'test_task' }
        subscriber.handle_task_start_requested(event)

        failure_event = { task_id: 'task-123', task_name: 'test_task', error_message: 'Test error' }

        expect(mock_span).to receive(:add_event)
          .with('task.failed', anything)

        expect(mock_span).to receive(:finish)

        subscriber.handle_task_failed(failure_event)

        # Verify span is removed after completion
        expect(subscriber.send(:get_task_span, 'task-123')).to be_nil
      end
    end

    describe 'step span creation' do
      before do
        # Create a task span first
        task_event = { task_id: 'task-123', task_name: 'test_task' }
        subscriber.handle_task_start_requested(task_event)
      end

      it 'creates child spans for step completion events' do
        step_event = { task_id: 'task-123', step_id: 'step-456', step_name: 'test_step' }

        expect(OpenTelemetry::Trace).to receive(:context_with_span)
          .with(mock_span)
          .and_return(mock_span_context)

        expect(OpenTelemetry::Context).to receive(:with_current)
          .with(mock_span_context)
          .and_yield

        expect(mock_tracer).to receive(:in_span)
          .with('tasker.step.execution', hash_including(:attributes))
          .and_yield(mock_span)

        expect(mock_span).to receive(:add_event)
          .with('step.completed', anything)

        subscriber.handle_step_completed(step_event)
      end

      it 'creates child spans for step failure events with error status' do
        step_event = { task_id: 'task-123', step_id: 'step-456', step_name: 'test_step', error_message: 'Step failed' }

        expect(mock_tracer).to receive(:in_span)
          .with('tasker.step.execution', hash_including(:attributes))
          .and_yield(mock_span)

        expect(mock_span).to receive(:add_event)
          .with('step.failed', anything)

        subscriber.handle_step_failed(step_event)
      end

      it 'handles missing task spans gracefully' do
        # Try to create step span without a parent task span
        step_event = { task_id: 'non-existent-task', step_id: 'step-456', step_name: 'test_step' }

        # Should not attempt to create span
        expect(mock_tracer).not_to receive(:in_span)

        expect { subscriber.handle_step_completed(step_event) }.not_to raise_error
      end
    end

    describe 'span attribute handling' do
      it 'converts attributes to OpenTelemetry format with service prefix' do
        attributes = { task_id: 'task-123', step_name: 'test_step', execution_duration: 1.23 }

        converted = subscriber.send(:convert_attributes_for_otel, attributes)

        expect(converted).to include(
          'tasker.task_id' => 'task-123',
          'tasker.step_name' => 'test_step',
          'tasker.execution_duration' => '1.23'
        )
      end

      it 'filters sensitive data from attributes' do
        filter_double = double
        allow(filter_double).to receive(:filter_param) do |key, value|
          key == 'password' ? '[FILTERED]' : value
        end
        allow(Tasker::Configuration.configuration).to receive(:parameter_filter)
          .and_return(filter_double)

        attributes = { task_id: 'task-123', password: 'secret123' }

        converted = subscriber.send(:convert_attributes_for_otel, attributes)

        expect(converted['tasker.task_id']).to eq('task-123')
        expect(converted['tasker.password']).to eq('[FILTERED]')
      end

      it 'handles complex data types by converting to JSON' do
        attributes = {
          task_id: 'task-123',
          complex_data: { nested: { array: [1, 2, 3] } },
          array_data: %w[a b c]
        }

        converted = subscriber.send(:convert_attributes_for_otel, attributes)

        expect(converted['tasker.complex_data']).to eq({ nested: { array: [1, 2, 3] } }.to_json)
        expect(converted['tasker.array_data']).to eq(%w[a b c].to_json)
      end
    end

    describe 'error handling' do
      it 'handles OpenTelemetry errors gracefully without breaking event processing' do
        allow(mock_tracer).to receive(:start_root_span).and_raise(StandardError, 'OpenTelemetry error')

        expect(Rails.logger).to receive(:warn).with(/Failed to create task span/)

        # Should not raise error
        expect { subscriber.handle_task_start_requested({ task_id: 'task-123' }) }.not_to raise_error
      end

      it 'handles span context errors gracefully' do
        # Create a task span first
        task_event = { task_id: 'task-123', task_name: 'test_task' }
        subscriber.handle_task_start_requested(task_event)

        allow(OpenTelemetry::Trace).to receive(:context_with_span).and_raise(StandardError, 'Context error')

        expect(Rails.logger).to receive(:warn).with(/Failed to create step span/)

        # Should not raise error
        expect { subscriber.handle_step_completed({ task_id: 'task-123', step_id: 'step-456' }) }.not_to raise_error
      end
    end
  end

  describe 'span status handling' do
    let(:mock_span) { instance_double(OpenTelemetry::Trace::Span, 'status=' => nil) }
    let(:mock_status_ok) { double('status_ok') }
    let(:mock_status_error) { double('status_error') }

    before do
      status_class = double('OpenTelemetry::Trace::Status')
      stub_const('OpenTelemetry::Trace::Status', status_class)
      allow(status_class).to receive_messages(ok: mock_status_ok, error: mock_status_error)
    end

    it 'sets OK status for successful operations' do
      expect(mock_span).to receive(:status=).with(mock_status_ok)

      subscriber.send(:set_span_status, mock_span, :ok, {})
    end

    it 'sets error status with message for failed operations' do
      attributes = { error: 'Test error message' }

      expect(OpenTelemetry::Trace::Status).to receive(:error).with('Test error message').and_return(mock_status_error)
      expect(mock_span).to receive(:status=).with(mock_status_error)

      subscriber.send(:set_span_status, mock_span, :error, attributes)
    end

    it 'handles missing error messages gracefully' do
      expect(OpenTelemetry::Trace::Status).to receive(:error).with('Unknown error').and_return(mock_status_error)
      expect(mock_span).to receive(:status=).with(mock_status_error)

      subscriber.send(:set_span_status, mock_span, :error, {})
    end

    it 'handles status setting errors gracefully' do
      allow(mock_span).to receive(:status=).and_raise(StandardError, 'Status error')

      expect(Rails.logger).to receive(:debug)

      # Should not raise error
      expect { subscriber.send(:set_span_status, mock_span, :ok, {}) }.not_to raise_error
    end
  end

  describe 'telemetry filtering' do
    describe 'when telemetry is disabled' do
      before do
        allow(Tasker.configuration).to receive(:enable_telemetry).and_return(false)
      end

      it 'skips processing events' do
        event = { task_id: 'task-123' }

        # Should not create any spans when telemetry is disabled
        expect(subscriber).not_to receive(:create_task_span)

        subscriber.handle_task_start_requested(event)
      end
    end

    describe 'when telemetry is enabled' do
      before do
        allow(Tasker.configuration).to receive(:enable_telemetry).and_return(true)
        allow(subscriber).to receive(:opentelemetry_available?).and_return(false)
      end

      it 'processes events normally' do
        event = { task_id: 'task-123' }

        # Should process the event (though won't create spans without OpenTelemetry)
        expect { subscriber.handle_task_start_requested(event) }.not_to raise_error
      end
    end
  end

  describe 'integration with real task workflow' do
    let(:mock_tracer) { instance_double(OpenTelemetry::Trace::Tracer) }
    let(:task_span) { instance_double(OpenTelemetry::Trace::Span, add_event: nil, finish: nil, 'status=' => nil) }
    let(:step_span) { instance_double(OpenTelemetry::Trace::Span, add_event: nil, 'status=' => nil) }

    before do
      # Mock OpenTelemetry availability

      # Mock tracer and spans
      allow(subscriber).to receive_messages(opentelemetry_available?: true, get_tracer: mock_tracer)
      allow(mock_tracer).to receive(:start_root_span).and_return(task_span)
      allow(mock_tracer).to receive(:in_span).and_yield(step_span)

      # Mock span context management
      allow(OpenTelemetry::Trace).to receive(:context_with_span).and_return(double)
      allow(OpenTelemetry::Context).to receive(:with_current).and_yield

      # Allow status setting
      allow(task_span).to receive(:status=)
      allow(step_span).to receive(:status=)
    end

    it 'handles a complete task workflow correctly' do
      # Start task
      task_start_event = { task_id: 'workflow-123', task_name: 'test_workflow' }
      subscriber.handle_task_start_requested(task_start_event)

      # Complete steps
      step1_event = { task_id: 'workflow-123', step_id: 'step1', step_name: 'fetch_data' }
      subscriber.handle_step_completed(step1_event)

      step2_event = { task_id: 'workflow-123', step_id: 'step2', step_name: 'process_data' }
      subscriber.handle_step_completed(step2_event)

      # Complete task
      task_complete_event = { task_id: 'workflow-123', task_name: 'test_workflow' }
      subscriber.handle_task_completed(task_complete_event)

      # Verify workflow completed without errors
      expect(subscriber.send(:get_task_span, 'workflow-123')).to be_nil
    end

    it 'handles task failure workflow correctly' do
      # Start task
      task_start_event = { task_id: 'failed-123', task_name: 'failing_workflow' }
      subscriber.handle_task_start_requested(task_start_event)

      # Complete one step
      step1_event = { task_id: 'failed-123', step_id: 'step1', step_name: 'fetch_data' }
      subscriber.handle_step_completed(step1_event)

      # Fail a step
      step2_event = { task_id: 'failed-123', step_id: 'step2', step_name: 'failing_step',
                      error_message: 'Network timeout' }
      subscriber.handle_step_failed(step2_event)

      # Fail task
      task_failure_event = { task_id: 'failed-123', task_name: 'failing_workflow', error_message: 'Step failed' }
      subscriber.handle_task_failed(task_failure_event)

      # Verify workflow completed (even with failure)
      expect(subscriber.send(:get_task_span, 'failed-123')).to be_nil
    end
  end
end
