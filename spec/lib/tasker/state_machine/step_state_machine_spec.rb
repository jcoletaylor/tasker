# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::StateMachine::StepStateMachine do
  # Use real factory-created objects instead of mocks
  let(:task) { create(:task) }
  let(:step) { create(:workflow_step, task: task) }
  let(:state_machine) { step.state_machine }

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
    context 'when transitioning from pending state' do
      it 'can transition to in_progress' do
        expect(state_machine.can_transition_to?(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)).to be true
      end

      it 'can transition to cancelled' do
        expect(state_machine.can_transition_to?(Tasker::Constants::WorkflowStepStatuses::CANCELLED)).to be true
      end

      it 'cannot transition to complete directly (must go through in_progress)' do
        expect(state_machine.can_transition_to?(Tasker::Constants::WorkflowStepStatuses::COMPLETE)).to be false
      end

      it 'can transition to resolved_manually for manual resolution' do
        expect(state_machine.can_transition_to?(Tasker::Constants::WorkflowStepStatuses::RESOLVED_MANUALLY)).to be true
      end
    end

    context 'when transitioning from in_progress state' do
      before do
        # Transition to in_progress using the state machine
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

    context 'when transitioning from error state' do
      before do
        # Transition through the states using the state machine
        state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
        state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::ERROR)
      end

      it 'can transition to pending for retry' do
        expect(state_machine.can_transition_to?(Tasker::Constants::WorkflowStepStatuses::PENDING)).to be true
      end

      it 'cannot transition to complete directly' do
        expect(state_machine.can_transition_to?(Tasker::Constants::WorkflowStepStatuses::COMPLETE)).to be false
      end
    end
  end

  describe 'guard clauses' do
    describe 'transition to in_progress' do
      it 'allows transition when step is pending and dependencies are met' do
        expect(step.status).to eq(Tasker::Constants::WorkflowStepStatuses::PENDING)
        expect { state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS) }.not_to raise_error
      end

      it 'prevents transition when dependencies are not met' do
        # Create a step with dependencies that aren't complete
        parent_step = create(:workflow_step, task: task)
        create(:workflow_step_edge, from_step: parent_step, to_step: step)

        # Parent step is still pending, so transition should fail
        expect { state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS) }
          .to raise_error(Statesman::GuardFailedError)
      end

      it 'allows transition when dependencies are complete' do
        # Create a step with completed dependencies
        parent_step = create(:workflow_step, task: task)
        create(:workflow_step_edge, from_step: parent_step, to_step: step)

        # Complete the parent step
        parent_step.state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
        parent_step.state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::COMPLETE)

        # Now the dependent step should be able to transition
        expect { state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS) }.not_to raise_error
      end

      it 'prevents transition when step is not pending' do
        # First transition to complete state
        state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
        state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::COMPLETE)

        expect { state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS) }
          .to raise_error(Statesman::TransitionFailedError)
      end
    end

    describe 'transition to complete' do
      before do
        # Transition to in_progress first
        state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
      end

      it 'allows transition when step is in_progress' do
        expect { state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::COMPLETE) }.not_to raise_error
      end
    end

    describe 'transition to pending from error' do
      before do
        # Transition through the states to error
        state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
        state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::ERROR)
      end

      it 'allows retry transition from error state' do
        expect { state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::PENDING) }.not_to raise_error
      end
    end
  end

  describe 'callbacks and lifecycle events' do
    it 'fires lifecycle events on state transitions' do
      # Test that events are fired (we can check this through the transition history)
      expect { state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS) }.not_to raise_error

      # Verify the transition was recorded
      expect(step.workflow_step_transitions.count).to be >= 1
      latest_transition = step.workflow_step_transitions.where(most_recent: true).first
      expect(latest_transition.to_state).to eq(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
    end

    it 'creates proper transition history' do
      # Test full transition sequence
      state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
      state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::COMPLETE)

      # Verify transition history
      transitions = step.workflow_step_transitions.order(:sort_key)
      expect(transitions.last.to_state).to eq(Tasker::Constants::WorkflowStepStatuses::COMPLETE)
      expect(transitions.map(&:to_state)).to include(
        Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS,
        Tasker::Constants::WorkflowStepStatuses::COMPLETE
      )
    end
  end

  describe 'class methods' do
    describe '.step_dependencies_met?' do
      context 'with no dependencies' do
        it 'returns true when step has no parent steps' do
          expect(described_class.step_dependencies_met?(step)).to be true
        end
      end

      context 'with dependencies' do
        let(:parent_step) { create(:workflow_step, task: task) }

        before do
          create(:workflow_step_edge, from_step: parent_step, to_step: step)
        end

        it 'returns false when parent steps are pending' do
          expect(described_class.step_dependencies_met?(step)).to be false
        end

        it 'returns false when parent steps are in progress' do
          parent_step.state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
          expect(described_class.step_dependencies_met?(step)).to be false
        end

        it 'returns true when parent steps are complete' do
          parent_step.state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
          parent_step.state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::COMPLETE)
          expect(described_class.step_dependencies_met?(step)).to be true
        end

        it 'returns false when any parent step is in error' do
          parent_step.state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
          parent_step.state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::ERROR)
          expect(described_class.step_dependencies_met?(step)).to be false
        end
      end

      context 'with multiple dependencies' do
        let(:parent_step_1) { create(:workflow_step, task: task) }
        let(:parent_step_2) { create(:workflow_step, task: task) }

        before do
          create(:workflow_step_edge, from_step: parent_step_1, to_step: step)
          create(:workflow_step_edge, from_step: parent_step_2, to_step: step)
        end

        it 'returns false when only some parent steps are complete' do
          parent_step_1.state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
          parent_step_1.state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::COMPLETE)
          # parent_step_2 remains pending

          expect(described_class.step_dependencies_met?(step)).to be false
        end

        it 'returns true when all parent steps are complete' do
          [parent_step_1, parent_step_2].each do |parent|
            parent.state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
            parent.state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::COMPLETE)
          end

          expect(described_class.step_dependencies_met?(step)).to be true
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
        expect(described_class.determine_transition_event_name(nil, Tasker::Constants::WorkflowStepStatuses::PENDING))
          .to eq(Tasker::Constants::StepEvents::INITIALIZE_REQUESTED)

        expect(described_class.determine_transition_event_name(
                 Tasker::Constants::WorkflowStepStatuses::PENDING,
                 Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS
               )).to eq(Tasker::Constants::StepEvents::EXECUTION_REQUESTED)

        expect(described_class.determine_transition_event_name(
                 Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS,
                 Tasker::Constants::WorkflowStepStatuses::COMPLETE
               )).to eq(Tasker::Constants::StepEvents::COMPLETED)
      end
    end
  end

  describe 'integration with real workflow step model' do
    it 'properly integrates with step status method' do
      expect(step.status).to eq(Tasker::Constants::WorkflowStepStatuses::PENDING)

      state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
      expect(step.status).to eq(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)

      # Reload to ensure database persistence
      step.reload
      expect(step.status).to eq(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
    end

    it 'maintains state consistency across reloads' do
      state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
      original_state = step.status

      step.reload
      expect(step.status).to eq(original_state)
      expect(step.state_machine.current_state).to eq(original_state)
    end

    it 'properly handles step dependencies in real workflow scenarios' do
      # Create a realistic workflow with dependencies
      task_with_workflow = create(:task, :api_integration, :with_steps)
      steps = task_with_workflow.workflow_steps.includes(:named_step).order(:workflow_step_id)

      # Verify that steps with dependencies can't transition until parents are complete
      dependent_step = steps.last
      if dependent_step.parents.any?
        expect { dependent_step.state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS) }
          .to raise_error(Statesman::GuardFailedError)
      end
    end
  end
end
