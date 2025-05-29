# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::StateMachine::TaskStateMachine do
  # Use real factory-created task instead of mocks
  let(:task) { create(:task) }
  let(:state_machine) { task.state_machine }

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
        # Transition to in_progress using the state machine
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
        # Transition through the states using the state machine
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
        expect(task.status).to eq(Tasker::Constants::TaskStatuses::PENDING)
        expect { state_machine.transition_to!(Tasker::Constants::TaskStatuses::IN_PROGRESS) }.not_to raise_error
      end

      it 'prevents transition when task is not pending' do
        # First transition to complete state
        state_machine.transition_to!(Tasker::Constants::TaskStatuses::IN_PROGRESS)
        state_machine.transition_to!(Tasker::Constants::TaskStatuses::COMPLETE)

        expect { state_machine.transition_to!(Tasker::Constants::TaskStatuses::IN_PROGRESS) }
          .to raise_error(Statesman::TransitionFailedError)
      end
    end

    describe 'transition to complete' do
      let(:task_with_steps) { create(:task, :with_steps) }
      let(:state_machine_with_steps) { task_with_steps.state_machine }

      before do
        # Transition to in_progress first
        state_machine_with_steps.transition_to!(Tasker::Constants::TaskStatuses::IN_PROGRESS)
      end

      it 'allows transition when task is in_progress and has no incomplete steps' do
        # Mark all steps as complete to allow task completion
        task_with_steps.workflow_steps.each do |step|
          step.state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
          step.state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::COMPLETE)
        end

        expect { state_machine_with_steps.transition_to!(Tasker::Constants::TaskStatuses::COMPLETE) }.not_to raise_error
      end

      it 'prevents transition when task has incomplete steps' do
        # Leave steps incomplete
        expect { state_machine_with_steps.transition_to!(Tasker::Constants::TaskStatuses::COMPLETE) }
          .to raise_error(Statesman::GuardFailedError)
      end
    end
  end

  describe 'callbacks and lifecycle events' do
    it 'fires lifecycle events on state transitions' do
      # Test that events are fired (we can check this through the transition history)
      expect { state_machine.transition_to!(Tasker::Constants::TaskStatuses::IN_PROGRESS) }.not_to raise_error

      # Verify the transition was recorded (Statesman creates transitions as needed)
      expect(task.task_transitions.count).to be >= 1
      latest_transition = task.task_transitions.where(most_recent: true).first
      expect(latest_transition.to_state).to eq(Tasker::Constants::TaskStatuses::IN_PROGRESS)
    end

    it 'creates proper transition history' do
      # Test full transition sequence
      state_machine.transition_to!(Tasker::Constants::TaskStatuses::IN_PROGRESS)
      state_machine.transition_to!(Tasker::Constants::TaskStatuses::COMPLETE)

      # Verify transition history (check that we have the expected final states)
      transitions = task.task_transitions.order(:sort_key)
      expect(transitions.last.to_state).to eq(Tasker::Constants::TaskStatuses::COMPLETE)
      expect(transitions.map(&:to_state)).to include(
        Tasker::Constants::TaskStatuses::IN_PROGRESS,
        Tasker::Constants::TaskStatuses::COMPLETE
      )
    end
  end

  describe 'class methods' do
    describe '.task_has_incomplete_steps?' do
      context 'with incomplete steps' do
        let(:task_with_steps) { create(:task, :with_steps) }

        it 'returns true when task has pending steps' do
          expect(described_class.task_has_incomplete_steps?(task_with_steps)).to be true
        end

        it 'returns true when task has in_progress steps' do
          task_with_steps.workflow_steps.first.state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
          expect(described_class.task_has_incomplete_steps?(task_with_steps)).to be true
        end

        it 'returns true when task has error steps' do
          step = task_with_steps.workflow_steps.first
          step.state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
          step.state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::ERROR)
          expect(described_class.task_has_incomplete_steps?(task_with_steps)).to be true
        end
      end

      context 'with complete steps' do
        let(:task_with_steps) { create(:task, :with_steps) }

        before do
          # Complete all steps
          task_with_steps.workflow_steps.each do |step|
            step.state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
            step.state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::COMPLETE)
          end
        end

        it 'returns false when all steps are complete' do
          expect(described_class.task_has_incomplete_steps?(task_with_steps)).to be false
        end
      end

      context 'with no steps' do
        it 'returns false when task has no steps' do
          expect(described_class.task_has_incomplete_steps?(task)).to be false
        end
      end
    end

    describe '.safe_fire_event' do
      it 'handles event firing without errors' do
        expect { described_class.safe_fire_event('test.event', { test: 'data' }) }.not_to raise_error
      end
    end

    describe '.determine_transition_event_name' do
      it 'returns correct event names for transitions' do
        expect(described_class.determine_transition_event_name(nil, Tasker::Constants::TaskStatuses::PENDING))
          .to eq(Tasker::Constants::TaskEvents::INITIALIZE_REQUESTED)

        expect(described_class.determine_transition_event_name(
                 Tasker::Constants::TaskStatuses::PENDING,
                 Tasker::Constants::TaskStatuses::IN_PROGRESS
               )).to eq(Tasker::Constants::TaskEvents::START_REQUESTED)

        expect(described_class.determine_transition_event_name(
                 Tasker::Constants::TaskStatuses::IN_PROGRESS,
                 Tasker::Constants::TaskStatuses::COMPLETE
               )).to eq(Tasker::Constants::TaskEvents::COMPLETED)
      end
    end
  end

  describe 'integration with real task model' do
    it 'properly integrates with task status method' do
      expect(task.status).to eq(Tasker::Constants::TaskStatuses::PENDING)

      state_machine.transition_to!(Tasker::Constants::TaskStatuses::IN_PROGRESS)
      expect(task.status).to eq(Tasker::Constants::TaskStatuses::IN_PROGRESS)

      # Reload to ensure database persistence
      task.reload
      expect(task.status).to eq(Tasker::Constants::TaskStatuses::IN_PROGRESS)
    end

    it 'maintains state consistency across reloads' do
      state_machine.transition_to!(Tasker::Constants::TaskStatuses::IN_PROGRESS)
      original_state = task.status

      task.reload
      expect(task.status).to eq(original_state)
      expect(task.state_machine.current_state).to eq(original_state)
    end
  end
end
