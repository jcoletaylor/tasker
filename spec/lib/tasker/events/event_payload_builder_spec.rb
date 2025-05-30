# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Events::EventPayloadBuilder do
  include FactoryWorkflowHelpers

  let(:task) { create_dummy_task_workflow(reason: 'payload_test_task') }
  let(:step) do
    task.workflow_steps.first.tap do |step|
      step.update!(
        attempts: 2,
        retry_limit: 5,
        last_attempted_at: 30.seconds.ago,
        processed_at: 5.seconds.ago,
        results: { 'output' => 'test result' }  # Use string keys to match database storage
      )
    end
  end

  describe '.build_step_payload' do
    context 'for completed events' do
      let(:payload) do
        described_class.build_step_payload(step, task, event_type: :completed)
      end

      it 'includes all required telemetry keys' do
        # Core identifiers
        expect(payload[:task_id]).to eq(task.task_id)
        expect(payload[:step_id]).to eq(step.workflow_step_id)
        expect(payload[:step_name]).to eq(step.name)

        # Timing information
        expect(payload[:started_at]).to be_present
        expect(payload[:completed_at]).to be_present
        expect(payload[:execution_duration]).to be_a(Numeric)
        expect(payload[:execution_duration]).to be > 0

        # Retry tracking
        expect(payload[:attempt_number]).to eq(2)
        expect(payload[:retry_limit]).to eq(5)

        # Event metadata
        expect(payload[:event_type]).to eq('completed')
        expect(payload[:timestamp]).to be_present

        # Step results (expect string keys from database)
        expect(payload[:step_results]).to eq({ 'output' => 'test result' })
      end

      it 'calculates execution duration correctly' do
        expect(payload[:execution_duration]).to be_within(1.0).of(25.0)
      end
    end

    context 'for failed events' do
      let(:error_context) do
        {
          error: 'Test error occurred',
          error_message: 'Detailed error message',
          exception_object: StandardError.new('Test exception'),
          backtrace: ['line1.rb:10', 'line2.rb:20']
        }
      end

      let(:payload) do
        described_class.build_step_payload(
          step,
          task,
          event_type: :failed,
          additional_context: error_context
        )
      end

      it 'includes all required error telemetry keys' do
        # Core identifiers
        expect(payload[:task_id]).to eq(task.task_id)
        expect(payload[:step_id]).to eq(step.workflow_step_id)
        expect(payload[:step_name]).to eq(step.name)

        # Error information (standardized keys for TelemetrySubscriber)
        expect(payload[:error_message]).to eq('Detailed error message')
        expect(payload[:exception_class]).to eq('StandardError')
        expect(payload[:backtrace]).to eq(['line1.rb:10', 'line2.rb:20'])

        # Retry tracking
        expect(payload[:attempt_number]).to eq(2)

        # Event metadata
        expect(payload[:event_type]).to eq('failed')
      end

      it 'handles missing error information gracefully' do
        minimal_payload = described_class.build_step_payload(
          step,
          task,
          event_type: :failed
        )

        expect(minimal_payload[:error_message]).to eq('Unknown error')
        expect(minimal_payload[:exception_class]).to eq('StandardError')
      end
    end

    context 'for started events' do
      let(:step_with_inputs) do
        task.workflow_steps.first.tap do |step|
          step.update!(inputs: { 'param1' => 'value1', 'param2' => 'value2' })  # Use string keys
        end
      end

      let(:payload) do
        described_class.build_step_payload(step_with_inputs, task, event_type: :started)
      end

      it 'includes step inputs and dependencies' do
        expect(payload[:step_inputs]).to eq({ 'param1' => 'value1', 'param2' => 'value2' })
        expect(payload[:step_dependencies]).to be_an(Array)
      end
    end
  end

  describe '.build_task_payload' do
    context 'with incomplete task (not all steps complete)' do
      let(:incomplete_task) do
        create_dummy_task_workflow(reason: 'incomplete_payload_test').tap do |task|
          task.update!(created_at: 2.minutes.ago)

          # Complete only some steps (not all)
          steps = task.workflow_steps.to_a
          steps[0].update!(processed_at: 30.seconds.ago, processed: true)
          complete_step_via_state_machine(steps[0])

          # Leave other steps incomplete - steps[1], steps[2], steps[3] remain pending
        end
      end

      let(:payload) do
        described_class.build_task_payload(incomplete_task, event_type: :started)
      end

      it 'provides current execution duration but not total execution duration' do
        # Core identifiers
        expect(payload[:task_id]).to eq(incomplete_task.task_id)
        expect(payload[:task_name]).to eq(incomplete_task.named_task.name)

        # Timing information - no completed_at since not all steps complete
        expect(payload[:started_at]).to be_present
        expect(payload[:completed_at]).to be_nil

        # Duration tracking - current duration only, no total duration
        expect(payload[:total_execution_duration]).to be_nil
        expect(payload[:current_execution_duration]).to be_a(Numeric)
        expect(payload[:current_execution_duration]).to be > 0
        expect(payload[:current_execution_duration]).to be_within(10.0).of(120.0)  # ~2 minutes

        # Step statistics
        expect(payload[:total_steps]).to eq(4)  # dummy workflow has 4 steps
        expect(payload[:completed_steps]).to eq(1)  # Only first step completed
        expect(payload[:failed_steps]).to eq(0)
        expect(payload[:pending_steps]).to eq(3)  # 3 steps still pending
      end
    end

    context 'with fully completed task (all steps complete)' do
      let(:completed_task) do
        create_dummy_task_workflow(reason: 'completed_payload_test').tap do |task|
          # Update with realistic timestamps
          task.update!(created_at: 2.minutes.ago)

          # Complete ALL steps with different completion times
          steps = task.workflow_steps.to_a
          steps[0].update!(processed_at: 50.seconds.ago, processed: true)
          steps[1].update!(processed_at: 30.seconds.ago, processed: true)
          steps[2].update!(processed_at: 20.seconds.ago, processed: true)
          steps[3].update!(processed_at: 10.seconds.ago, processed: true)  # This should be the latest

          # Mark ALL steps as complete via state machine
          steps.each { |step| complete_step_via_state_machine(step) }
        end
      end

      let(:payload) do
        described_class.build_task_payload(completed_task, event_type: :completed)
      end

      it 'provides total execution duration and infers completion time' do
        # Core identifiers
        expect(payload[:task_id]).to eq(completed_task.task_id)
        expect(payload[:task_name]).to eq(completed_task.named_task.name)

        # Timing information - should be inferred since ALL steps complete
        expect(payload[:started_at]).to be_present
        expect(payload[:completed_at]).to be_present

        # Duration tracking - total duration available since all steps complete
        expect(payload[:total_execution_duration]).to be_a(Numeric)
        expect(payload[:total_execution_duration]).to be > 0
        expect(payload[:current_execution_duration]).to be_nil  # Not applicable for completed tasks
        # Should be roughly 110 seconds (2 minutes - 10 seconds), allowing for test execution variance
        expect(payload[:total_execution_duration]).to be_within(15.0).of(110.0)

        # Task metadata
        expect(payload[:task_type]).to eq('Tasker::Task')
        expect(payload[:event_type]).to eq('completed')
        expect(payload[:timestamp]).to be_present

        # Step statistics - all steps should be complete
        expect(payload[:total_steps]).to eq(4)
        expect(payload[:completed_steps]).to eq(4)  # All steps completed
        expect(payload[:failed_steps]).to eq(0)
        expect(payload[:pending_steps]).to eq(0)  # No pending steps
      end
    end

    context 'with no completed steps' do
      let(:fresh_task) do
        create_dummy_task_workflow(reason: 'fresh_payload_test').tap do |task|
          task.update!(created_at: 1.minute.ago)
          # Don't complete any steps - leave them all in pending state
        end
      end

      let(:payload) do
        described_class.build_task_payload(fresh_task, event_type: :started)
      end

      it 'provides current execution duration but no completion information' do
        # Core identifiers
        expect(payload[:task_id]).to eq(fresh_task.task_id)
        expect(payload[:task_name]).to eq(fresh_task.named_task.name)

        # Timing information - no completion time
        expect(payload[:started_at]).to be_present
        expect(payload[:completed_at]).to be_nil

        # Duration tracking - current duration only
        expect(payload[:total_execution_duration]).to be_nil
        expect(payload[:current_execution_duration]).to be_a(Numeric)
        expect(payload[:current_execution_duration]).to be_within(5.0).of(60.0)  # ~1 minute

        # Step statistics
        expect(payload[:total_steps]).to eq(4)
        expect(payload[:completed_steps]).to eq(0)  # No steps completed
        expect(payload[:failed_steps]).to eq(0)
        expect(payload[:pending_steps]).to eq(4)  # All steps pending
      end
    end

    context 'for failed events' do
      let(:error_context) do
        {
          error_message: 'Task failed due to step errors',
          error_steps: 'step1, step2',
          error_step_results: [
            { step_id: 'step1', step_name: 'first_step', step_results: { error: 'failed' } }
          ]
        }
      end

      let(:payload) do
        described_class.build_task_payload(
          task,
          event_type: :failed,
          additional_context: error_context
        )
      end

      it 'includes task error information' do
        expect(payload[:error_message]).to eq('Task failed due to step errors')
        expect(payload[:error_steps]).to eq('step1, step2')
        expect(payload[:error_step_results]).to be_an(Array)
        expect(payload[:error_step_results].first[:step_name]).to eq('first_step')
      end
    end
  end

  describe '.build_orchestration_payload' do
    let(:context) do
      {
        task_id: 'orchestration-task',
        step_ids: ['step1', 'step2'],
        processing_mode: 'concurrent'
      }
    end

    let(:payload) do
      described_class.build_orchestration_payload(
        event_type: :viable_steps_discovered,
        context: context
      )
    end

    it 'includes orchestration metadata' do
      expect(payload[:event_type]).to eq('viable_steps_discovered')
      expect(payload[:orchestration_event]).to be true
      expect(payload[:timestamp]).to be_present

      # Context is merged in
      expect(payload[:task_id]).to eq('orchestration-task')
      expect(payload[:step_ids]).to eq(['step1', 'step2'])
      expect(payload[:processing_mode]).to eq('concurrent')
    end
  end
end
