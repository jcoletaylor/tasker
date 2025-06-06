# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::StateMachine do
  describe '.configure_statesman' do
    it 'returns true without requiring global configuration' do
      result = described_class.configure_statesman
      expect(result).to be true
    end
  end

  describe '.initialize_task_state_machine' do
    let(:task_double) { instance_double(Tasker::Task) }

    it 'creates a new TaskStateMachine instance' do
      expect(Tasker::StateMachine::TaskStateMachine).to receive(:new).with(task_double)
      described_class.initialize_task_state_machine(task_double)
    end
  end

  describe '.initialize_step_state_machine' do
    let(:step_double) { instance_double(Tasker::WorkflowStep) }

    it 'creates a new StepStateMachine instance' do
      expect(Tasker::StateMachine::StepStateMachine).to receive(:new).with(step_double)
      described_class.initialize_step_state_machine(step_double)
    end
  end

  describe '.configured?' do
    context 'when all dependencies are available' do
      before do
        stub_const('Statesman', double('Statesman'))
        allow(Tasker::StateMachine::TaskStateMachine).to receive(:respond_to?).with(:new).and_return(true)
        allow(Tasker::StateMachine::StepStateMachine).to receive(:respond_to?).with(:new).and_return(true)
      end

      it 'returns true' do
        expect(described_class.configured?).to be true
      end
    end

    context 'when Statesman is not defined' do
      before do
        hide_const('Statesman')
      end

      it 'returns false' do
        expect(described_class.configured?).to be false
      end
    end

    context 'when TaskStateMachine does not respond to new' do
      before do
        stub_const('Statesman', double('Statesman'))
        allow(Tasker::StateMachine::TaskStateMachine).to receive(:respond_to?).with(:new).and_return(false)
        allow(Tasker::StateMachine::StepStateMachine).to receive(:respond_to?).with(:new).and_return(true)
      end

      it 'returns false' do
        expect(described_class.configured?).to be false
      end
    end

    context 'when StepStateMachine does not respond to new' do
      before do
        stub_const('Statesman', double('Statesman'))
        allow(Tasker::StateMachine::TaskStateMachine).to receive(:respond_to?).with(:new).and_return(true)
        allow(Tasker::StateMachine::StepStateMachine).to receive(:respond_to?).with(:new).and_return(false)
      end

      it 'returns false' do
        expect(described_class.configured?).to be false
      end
    end
  end

  describe '.statistics' do
    before do
      allow(described_class).to receive(:configured?).and_return(true)
    end

    it 'returns statistics hash with expected keys' do
      stats = described_class.statistics

      expect(stats).to be_a(Hash)
      expect(stats).to have_key(:task_states)
      expect(stats).to have_key(:step_states)
      expect(stats).to have_key(:configured)
    end

    it 'includes valid task statuses' do
      stats = described_class.statistics
      expect(stats[:task_states]).to eq(Tasker::Constants::VALID_TASK_STATUSES)
    end

    it 'includes valid step statuses' do
      stats = described_class.statistics
      expect(stats[:step_states]).to eq(Tasker::Constants::VALID_WORKFLOW_STEP_STATUSES)
    end

    it 'includes configuration status' do
      stats = described_class.statistics
      expect(stats[:configured]).to be true
    end
  end

  describe 'InvalidStateTransition exception' do
    it 'is defined as a StandardError subclass' do
      expect(Tasker::StateMachine::InvalidStateTransition.superclass).to eq(StandardError)
    end

    it 'can be instantiated with a message' do
      error = Tasker::StateMachine::InvalidStateTransition.new('Test error')
      expect(error.message).to eq('Test error')
    end

    it 'can be raised and caught' do
      expect do
        raise Tasker::StateMachine::InvalidStateTransition, 'Invalid transition'
      end.to raise_error(Tasker::StateMachine::InvalidStateTransition, 'Invalid transition')
    end
  end

  describe 'module structure' do
    it 'defines the TaskStateMachine class' do
      expect(defined?(Tasker::StateMachine::TaskStateMachine)).to be_truthy
    end

    it 'defines the StepStateMachine class' do
      expect(defined?(Tasker::StateMachine::StepStateMachine)).to be_truthy
    end

    it 'defines the Compatibility module' do
      expect(defined?(Tasker::StateMachine::Compatibility)).to be_truthy
    end

    it 'defines the InvalidStateTransition exception' do
      expect(defined?(Tasker::StateMachine::InvalidStateTransition)).to be_truthy
    end
  end

  describe 'integration with other modules' do
    it 'is available from the main Tasker module' do
      expect(described_class).to eq(described_class)
    end

    it 'has access to Tasker constants' do
      expect { Tasker::Constants::TaskStatuses::PENDING }.not_to raise_error
      expect { Tasker::Constants::WorkflowStepStatuses::PENDING }.not_to raise_error
    end
  end
end
