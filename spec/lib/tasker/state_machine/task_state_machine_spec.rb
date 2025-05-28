# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::StateMachine::TaskStateMachine do
  let(:task_double) do
    instance_double(
      Tasker::Task,
      task_id: 123,
      name: 'test_task',
      context: { test: 'data' },
      status: Tasker::Constants::TaskStatuses::PENDING,
      'update_column' => true,
      'respond_to?' => true
    )
  end

  let(:state_machine) { described_class.new(task_double) }

  before do
    # Stub the safe_fire_event method to avoid lifecycle event dependencies
    allow_any_instance_of(described_class).to receive(:safe_fire_event)
    allow_any_instance_of(described_class).to receive(:task_has_incomplete_steps?).and_return(false)
  end

  describe '#initialize' do
    it 'creates a state machine instance' do
      expect(state_machine).to be_a(described_class)
    end

    it 'sets the correct initial state' do
      expect(state_machine.current_state).to eq(Tasker::Constants::TaskStatuses::PENDING)
    end
  end

  describe 'state definitions' do
    it 'defines all required task states' do
      expected_states = [
        Tasker::Constants::TaskStatuses::PENDING,
        Tasker::Constants::TaskStatuses::IN_PROGRESS,
        Tasker::Constants::TaskStatuses::COMPLETE,
        Tasker::Constants::TaskStatuses::ERROR,
        Tasker::Constants::TaskStatuses::CANCELLED,
        Tasker::Constants::TaskStatuses::RESOLVED_MANUALLY
      ]

      expected_states.each do |state|
        expect(described_class.states).to include(state)
      end
    end

    it 'sets pending as the initial state' do
      expect(described_class.initial_state).to eq(Tasker::Constants::TaskStatuses::PENDING)
    end
  end

  describe 'valid transitions' do
    context 'from pending state' do
      it 'can transition to in_progress' do
        expect(state_machine.can_transition_to?(Tasker::Constants::TaskStatuses::IN_PROGRESS)).to be true
      end

      it 'can transition to cancelled' do
        expect(state_machine.can_transition_to?(Tasker::Constants::TaskStatuses::CANCELLED)).to be true
      end

      it 'cannot transition to complete directly' do
        expect(state_machine.can_transition_to?(Tasker::Constants::TaskStatuses::COMPLETE)).to be false
      end
    end

    context 'from in_progress state' do
      before do
        allow(task_double).to receive(:status).and_return(Tasker::Constants::TaskStatuses::IN_PROGRESS)
        state_machine.transition_to!(Tasker::Constants::TaskStatuses::IN_PROGRESS)
      end

      it 'can transition to complete' do
        expect(state_machine.can_transition_to?(Tasker::Constants::TaskStatuses::COMPLETE)).to be true
      end

      it 'can transition to error' do
        expect(state_machine.can_transition_to?(Tasker::Constants::TaskStatuses::ERROR)).to be true
      end

      it 'can transition to cancelled' do
        expect(state_machine.can_transition_to?(Tasker::Constants::TaskStatuses::CANCELLED)).to be true
      end

      it 'can transition back to pending' do
        expect(state_machine.can_transition_to?(Tasker::Constants::TaskStatuses::PENDING)).to be true
      end
    end

    context 'from error state' do
      before do
        allow(task_double).to receive(:status).and_return(Tasker::Constants::TaskStatuses::ERROR)
        state_machine.transition_to!(Tasker::Constants::TaskStatuses::IN_PROGRESS)
        state_machine.transition_to!(Tasker::Constants::TaskStatuses::ERROR)
      end

      it 'can transition to pending for retry' do
        expect(state_machine.can_transition_to?(Tasker::Constants::TaskStatuses::PENDING)).to be true
      end

      it 'can transition to resolved_manually' do
        expect(state_machine.can_transition_to?(Tasker::Constants::TaskStatuses::RESOLVED_MANUALLY)).to be true
      end

      it 'cannot transition to complete directly' do
        expect(state_machine.can_transition_to?(Tasker::Constants::TaskStatuses::COMPLETE)).to be false
      end
    end
  end

  describe 'guard clauses' do
    describe 'transition to in_progress' do
      it 'allows transition when task status is pending' do
        allow(task_double).to receive(:status).and_return(Tasker::Constants::TaskStatuses::PENDING)
        expect { state_machine.transition_to!(Tasker::Constants::TaskStatuses::IN_PROGRESS) }.not_to raise_error
      end

      it 'prevents transition when task is not pending' do
        allow(task_double).to receive(:status).and_return(Tasker::Constants::TaskStatuses::COMPLETE)
        expect { state_machine.transition_to!(Tasker::Constants::TaskStatuses::IN_PROGRESS) }
          .to raise_error(Statesman::GuardFailedError)
      end
    end

    describe 'transition to complete' do
      before do
        allow(task_double).to receive(:status).and_return(Tasker::Constants::TaskStatuses::IN_PROGRESS)
        state_machine.transition_to!(Tasker::Constants::TaskStatuses::IN_PROGRESS)
      end

      it 'allows transition when task is in_progress and has no incomplete steps' do
        allow_any_instance_of(described_class).to receive(:task_has_incomplete_steps?).and_return(false)
        expect { state_machine.transition_to!(Tasker::Constants::TaskStatuses::COMPLETE) }.not_to raise_error
      end

      it 'prevents transition when task has incomplete steps' do
        allow_any_instance_of(described_class).to receive(:task_has_incomplete_steps?).and_return(true)
        expect { state_machine.transition_to!(Tasker::Constants::TaskStatuses::COMPLETE) }
          .to raise_error(Statesman::GuardFailedError)
      end
    end
  end

  describe 'callbacks' do
    it 'fires before_transition events' do
      expect_any_instance_of(described_class).to receive(:safe_fire_event)
        .with('task.before_transition', hash_including(
                                          task_id: 123,
                                          from_state: Tasker::Constants::TaskStatuses::PENDING,
                                          to_state: Tasker::Constants::TaskStatuses::IN_PROGRESS
                                        ))

      state_machine.transition_to!(Tasker::Constants::TaskStatuses::IN_PROGRESS)
    end

    it 'fires after_transition events with appropriate event name' do
      expect_any_instance_of(described_class).to receive(:safe_fire_event)
        .with('task.start_requested', hash_including(
                                        task_id: 123,
                                        task_name: 'test_task',
                                        from_state: Tasker::Constants::TaskStatuses::PENDING,
                                        to_state: Tasker::Constants::TaskStatuses::IN_PROGRESS
                                      ))

      state_machine.transition_to!(Tasker::Constants::TaskStatuses::IN_PROGRESS)
    end

    it 'updates the task status in database' do
      expect(task_double).to receive(:update_column).with(:status, Tasker::Constants::TaskStatuses::IN_PROGRESS)
      state_machine.transition_to!(Tasker::Constants::TaskStatuses::IN_PROGRESS)
    end
  end

  describe 'class methods' do
    describe '.can_transition?' do
      it 'returns true for valid transitions' do
        expect(described_class.can_transition?(task_double, Tasker::Constants::TaskStatuses::IN_PROGRESS)).to be true
      end

      it 'returns false for invalid transitions' do
        expect(described_class.can_transition?(task_double, Tasker::Constants::TaskStatuses::COMPLETE)).to be false
      end
    end

    describe '.allowed_transitions' do
      it 'returns array of allowed target states' do
        allowed = described_class.allowed_transitions(task_double)
        expect(allowed).to include(Tasker::Constants::TaskStatuses::IN_PROGRESS)
        expect(allowed).to include(Tasker::Constants::TaskStatuses::CANCELLED)
        expect(allowed).not_to include(Tasker::Constants::TaskStatuses::COMPLETE)
      end
    end

    describe '.transition_to!' do
      it 'successfully transitions to valid state' do
        expect(described_class.transition_to!(task_double, Tasker::Constants::TaskStatuses::IN_PROGRESS)).to be true
      end

      it 'raises error for invalid state' do
        expect { described_class.transition_to!(task_double, Tasker::Constants::TaskStatuses::COMPLETE) }
          .to raise_error(Statesman::TransitionFailedError)
      end
    end

    describe '.current_state' do
      it 'returns task status or default pending' do
        expect(described_class.current_state(task_double)).to eq(Tasker::Constants::TaskStatuses::PENDING)
      end

      it 'returns pending when status is nil' do
        allow(task_double).to receive(:status).and_return(nil)
        expect(described_class.current_state(task_double)).to eq(Tasker::Constants::TaskStatuses::PENDING)
      end
    end
  end

  describe 'event name determination' do
    let(:transition_double) { instance_double(Statesman::Transition) }

    it 'returns correct event for start transition' do
      allow(transition_double).to receive_messages(from: Tasker::Constants::TaskStatuses::PENDING,
                                                   to: Tasker::Constants::TaskStatuses::IN_PROGRESS)

      event_name = state_machine.send(:transition_event_name, transition_double)
      expect(event_name).to eq('start_requested')
    end

    it 'returns correct event for completion transition' do
      allow(transition_double).to receive_messages(from: Tasker::Constants::TaskStatuses::IN_PROGRESS,
                                                   to: Tasker::Constants::TaskStatuses::COMPLETE)

      event_name = state_machine.send(:transition_event_name, transition_double)
      expect(event_name).to eq('completed')
    end

    it 'returns correct event for error transition' do
      allow(transition_double).to receive_messages(from: Tasker::Constants::TaskStatuses::IN_PROGRESS,
                                                   to: Tasker::Constants::TaskStatuses::ERROR)

      event_name = state_machine.send(:transition_event_name, transition_double)
      expect(event_name).to eq('failed')
    end

    it 'returns correct event for retry transition' do
      allow(transition_double).to receive_messages(from: Tasker::Constants::TaskStatuses::ERROR,
                                                   to: Tasker::Constants::TaskStatuses::PENDING)

      event_name = state_machine.send(:transition_event_name, transition_double)
      expect(event_name).to eq('retry_requested')
    end
  end

  describe 'incomplete steps checking' do
    let(:step_double_pending) do
      instance_double(Tasker::WorkflowStep, status: Tasker::Constants::WorkflowStepStatuses::PENDING)
    end
    let(:step_double_complete) do
      instance_double(Tasker::WorkflowStep, status: Tasker::Constants::WorkflowStepStatuses::COMPLETE)
    end

    before do
      allow_any_instance_of(described_class).to receive(:task_has_incomplete_steps?).and_call_original
    end

    it 'returns true when task has pending steps' do
      allow(task_double).to receive(:respond_to?).with(:workflow_steps).and_return(true)
      allow(task_double).to receive(:workflow_steps).and_return([step_double_pending, step_double_complete])

      result = state_machine.send(:task_has_incomplete_steps?, task_double)
      expect(result).to be true
    end

    it 'returns false when all steps are complete' do
      allow(task_double).to receive(:respond_to?).with(:workflow_steps).and_return(true)
      allow(task_double).to receive(:workflow_steps).and_return([step_double_complete])

      result = state_machine.send(:task_has_incomplete_steps?, task_double)
      expect(result).to be false
    end

    it 'returns false when task does not respond to workflow_steps' do
      allow(task_double).to receive(:respond_to?).with(:workflow_steps).and_return(false)

      result = state_machine.send(:task_has_incomplete_steps?, task_double)
      expect(result).to be false
    end
  end

  describe 'error handling' do
    it 'handles lifecycle event errors gracefully' do
      allow_any_instance_of(described_class).to receive(:safe_fire_event).and_raise(StandardError.new('Event error'))

      expect { state_machine.transition_to!(Tasker::Constants::TaskStatuses::IN_PROGRESS) }.not_to raise_error
    end
  end
end
