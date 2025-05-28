# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::StateMachine::StepStateMachine do
  let(:task_double) do
    instance_double(
      Tasker::Task,
      task_id: 123,
      'respond_to?' => true
    )
  end

  let(:step_double) do
    instance_double(
      Tasker::WorkflowStep,
      workflow_step_id: 456,
      task_id: 123,
      name: 'test_step',
      inputs: { test: 'input' },
      results: { test: 'result' },
      status: Tasker::Constants::WorkflowStepStatuses::PENDING,
      'update_column' => true,
      'respond_to?' => true,
      depends_on_steps: [],
      task: task_double
    )
  end

  let(:state_machine) { described_class.new(step_double) }

  before do
    # Stub the safe_fire_event method to avoid lifecycle event dependencies
    allow_any_instance_of(described_class).to receive(:safe_fire_event)
    allow_any_instance_of(described_class).to receive(:step_dependencies_met?).and_return(true)
  end

  describe '#initialize' do
    it 'creates a state machine instance' do
      expect(state_machine).to be_a(described_class)
    end

    it 'sets the correct initial state' do
      expect(state_machine.current_state).to eq(Tasker::Constants::WorkflowStepStatuses::PENDING)
    end
  end

  describe 'state definitions' do
    it 'defines all required step states' do
      expected_states = [
        Tasker::Constants::WorkflowStepStatuses::PENDING,
        Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS,
        Tasker::Constants::WorkflowStepStatuses::COMPLETE,
        Tasker::Constants::WorkflowStepStatuses::ERROR,
        Tasker::Constants::WorkflowStepStatuses::CANCELLED,
        Tasker::Constants::WorkflowStepStatuses::RESOLVED_MANUALLY
      ]

      expected_states.each do |state|
        expect(described_class.states).to include(state)
      end
    end

    it 'sets pending as the initial state' do
      expect(described_class.initial_state).to eq(Tasker::Constants::WorkflowStepStatuses::PENDING)
    end
  end

  describe 'valid transitions' do
    context 'from pending state' do
      it 'can transition to in_progress' do
        expect(state_machine.can_transition_to?(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)).to be true
      end

      it 'can transition to cancelled' do
        expect(state_machine.can_transition_to?(Tasker::Constants::WorkflowStepStatuses::CANCELLED)).to be true
      end

      it 'cannot transition to complete directly' do
        expect(state_machine.can_transition_to?(Tasker::Constants::WorkflowStepStatuses::COMPLETE)).to be false
      end
    end

    context 'from in_progress state' do
      before do
        allow(step_double).to receive(:status).and_return(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
        state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
      end

      it 'can transition to complete' do
        expect(state_machine.can_transition_to?(Tasker::Constants::WorkflowStepStatuses::COMPLETE)).to be true
      end

      it 'can transition to error' do
        expect(state_machine.can_transition_to?(Tasker::Constants::WorkflowStepStatuses::ERROR)).to be true
      end

      it 'can transition to cancelled' do
        expect(state_machine.can_transition_to?(Tasker::Constants::WorkflowStepStatuses::CANCELLED)).to be true
      end
    end

    context 'from error state' do
      before do
        allow(step_double).to receive(:status).and_return(Tasker::Constants::WorkflowStepStatuses::ERROR)
        state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
        state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::ERROR)
      end

      it 'can transition to pending for retry' do
        expect(state_machine.can_transition_to?(Tasker::Constants::WorkflowStepStatuses::PENDING)).to be true
      end

      it 'can transition to resolved_manually' do
        expect(state_machine.can_transition_to?(Tasker::Constants::WorkflowStepStatuses::RESOLVED_MANUALLY)).to be true
      end

      it 'cannot transition to complete directly' do
        expect(state_machine.can_transition_to?(Tasker::Constants::WorkflowStepStatuses::COMPLETE)).to be false
      end
    end
  end

  describe 'guard clauses' do
    describe 'transition to in_progress' do
      it 'allows transition when step is pending and dependencies are met' do
        allow(step_double).to receive(:status).and_return(Tasker::Constants::WorkflowStepStatuses::PENDING)
        allow_any_instance_of(described_class).to receive(:step_dependencies_met?).and_return(true)
        expect { state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS) }.not_to raise_error
      end

      it 'prevents transition when dependencies are not met' do
        allow(step_double).to receive(:status).and_return(Tasker::Constants::WorkflowStepStatuses::PENDING)
        allow_any_instance_of(described_class).to receive(:step_dependencies_met?).and_return(false)
        expect { state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS) }
          .to raise_error(Statesman::GuardFailedError)
      end

      it 'prevents transition when step is not pending' do
        allow(step_double).to receive(:status).and_return(Tasker::Constants::WorkflowStepStatuses::COMPLETE)
        expect { state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS) }
          .to raise_error(Statesman::GuardFailedError)
      end
    end

    describe 'transition to complete' do
      before do
        allow(step_double).to receive(:status).and_return(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
        state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
      end

      it 'allows transition when step is in_progress' do
        expect { state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::COMPLETE) }.not_to raise_error
      end
    end

    describe 'transition to pending from error' do
      before do
        allow(step_double).to receive(:status).and_return(Tasker::Constants::WorkflowStepStatuses::ERROR)
        state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
        state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::ERROR)
      end

      it 'allows retry transition from error state' do
        expect { state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::PENDING) }.not_to raise_error
      end
    end
  end

  describe 'callbacks' do
    it 'fires before_transition events' do
      expect_any_instance_of(described_class).to receive(:safe_fire_event)
        .with('step.before_transition', hash_including(
                                          task_id: 123,
                                          step_id: 456,
                                          step_name: 'test_step',
                                          from_state: Tasker::Constants::WorkflowStepStatuses::PENDING,
                                          to_state: Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS
                                        ))

      state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
    end

    it 'fires after_transition events with appropriate event name' do
      expect_any_instance_of(described_class).to receive(:safe_fire_event)
        .with('step.execution_requested', hash_including(
                                            task_id: 123,
                                            step_id: 456,
                                            step_name: 'test_step',
                                            from_state: Tasker::Constants::WorkflowStepStatuses::PENDING,
                                            to_state: Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS
                                          ))

      state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
    end

    it 'updates the step status in database' do
      expect(step_double).to receive(:update_column).with(:status, Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
      state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
    end
  end

  describe 'class methods' do
    describe '.can_transition?' do
      it 'returns true for valid transitions' do
        expect(described_class.can_transition?(step_double,
                                               Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)).to be true
      end

      it 'returns false for invalid transitions' do
        expect(described_class.can_transition?(step_double,
                                               Tasker::Constants::WorkflowStepStatuses::COMPLETE)).to be false
      end
    end

    describe '.allowed_transitions' do
      it 'returns array of allowed target states' do
        allowed = described_class.allowed_transitions(step_double)
        expect(allowed).to include(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
        expect(allowed).to include(Tasker::Constants::WorkflowStepStatuses::CANCELLED)
        expect(allowed).not_to include(Tasker::Constants::WorkflowStepStatuses::COMPLETE)
      end
    end

    describe '.transition_to!' do
      it 'successfully transitions to valid state' do
        expect(described_class.transition_to!(step_double,
                                              Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)).to be true
      end

      it 'raises error for invalid state' do
        expect { described_class.transition_to!(step_double, Tasker::Constants::WorkflowStepStatuses::COMPLETE) }
          .to raise_error(Statesman::TransitionFailedError)
      end
    end

    describe '.current_state' do
      it 'returns step status or default pending' do
        expect(described_class.current_state(step_double)).to eq(Tasker::Constants::WorkflowStepStatuses::PENDING)
      end

      it 'returns pending when status is nil' do
        allow(step_double).to receive(:status).and_return(nil)
        expect(described_class.current_state(step_double)).to eq(Tasker::Constants::WorkflowStepStatuses::PENDING)
      end
    end
  end

  describe 'event name determination' do
    let(:transition_double) { instance_double(Statesman::Transition) }

    it 'returns correct event for execution transition' do
      allow(transition_double).to receive_messages(from: Tasker::Constants::WorkflowStepStatuses::PENDING,
                                                   to: Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)

      event_name = state_machine.send(:transition_event_name, transition_double)
      expect(event_name).to eq('execution_requested')
    end

    it 'returns correct event for completion transition' do
      allow(transition_double).to receive_messages(from: Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS,
                                                   to: Tasker::Constants::WorkflowStepStatuses::COMPLETE)

      event_name = state_machine.send(:transition_event_name, transition_double)
      expect(event_name).to eq('completed')
    end

    it 'returns correct event for error transition' do
      allow(transition_double).to receive_messages(from: Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS,
                                                   to: Tasker::Constants::WorkflowStepStatuses::ERROR)

      event_name = state_machine.send(:transition_event_name, transition_double)
      expect(event_name).to eq('failed')
    end

    it 'returns correct event for retry transition' do
      allow(transition_double).to receive_messages(from: Tasker::Constants::WorkflowStepStatuses::ERROR,
                                                   to: Tasker::Constants::WorkflowStepStatuses::PENDING)

      event_name = state_machine.send(:transition_event_name, transition_double)
      expect(event_name).to eq('retry_requested')
    end
  end

  describe 'dependency checking' do
    let(:dependent_step_1) do
      instance_double(Tasker::WorkflowStep,
                      workflow_step_id: 111,
                      status: Tasker::Constants::WorkflowStepStatuses::COMPLETE)
    end

    let(:dependent_step_2) do
      instance_double(Tasker::WorkflowStep,
                      workflow_step_id: 222,
                      status: Tasker::Constants::WorkflowStepStatuses::PENDING)
    end

    let(:workflow_steps_collection) { [dependent_step_1, dependent_step_2] }

    before do
      allow_any_instance_of(described_class).to receive(:step_dependencies_met?).and_call_original
    end

    context 'when step has no dependencies' do
      before do
        allow(step_double).to receive(:respond_to?).with(:depends_on_steps).and_return(true)
        allow(step_double).to receive(:depends_on_steps).and_return([])
      end

      it 'returns true' do
        result = state_machine.send(:step_dependencies_met?, step_double)
        expect(result).to be true
      end
    end

    context 'when step has dependencies' do
      before do
        allow(step_double).to receive(:respond_to?).with(:depends_on_steps).and_return(true)
        allow(step_double).to receive(:depends_on_steps).and_return(%w[dep_step_1 dep_step_2])
        allow(step_double).to receive(:respond_to?).with(:task).and_return(true)
        allow(task_double).to receive(:respond_to?).with(:workflow_steps).and_return(true)
        allow(task_double).to receive(:workflow_steps).and_return(workflow_steps_collection)
        allow(workflow_steps_collection).to receive(:where).with(name: %w[dep_step_1
                                                                          dep_step_2]).and_return([dependent_step_1,
                                                                                                   dependent_step_2])
      end

      it 'returns true when all dependencies are complete' do
        allow(dependent_step_2).to receive(:status).and_return(Tasker::Constants::WorkflowStepStatuses::COMPLETE)

        result = state_machine.send(:step_dependencies_met?, step_double)
        expect(result).to be true
      end

      it 'returns false when some dependencies are not complete' do
        result = state_machine.send(:step_dependencies_met?, step_double)
        expect(result).to be false
      end
    end

    context 'when step does not respond to depends_on_steps' do
      before do
        allow(step_double).to receive(:respond_to?).with(:depends_on_steps).and_return(false)
      end

      it 'returns true' do
        result = state_machine.send(:step_dependencies_met?, step_double)
        expect(result).to be true
      end
    end
  end

  describe 'error handling' do
    it 'handles lifecycle event errors gracefully' do
      allow_any_instance_of(described_class).to receive(:safe_fire_event).and_raise(StandardError.new('Event error'))

      expect { state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS) }.not_to raise_error
    end
  end
end
