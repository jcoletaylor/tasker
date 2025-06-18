# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Authorization::ResourceConstants do
  describe 'RESOURCES module' do
    it 'defines expected resource constants' do
      expect(described_class::RESOURCES::TASK).to eq('tasker.task')
      expect(described_class::RESOURCES::WORKFLOW_STEP).to eq('tasker.workflow_step')
      expect(described_class::RESOURCES::TASK_DIAGRAM).to eq('tasker.task_diagram')
    end

    describe '.all' do
      it 'returns all resource constants' do
        all_resources = described_class::RESOURCES.all

        expect(all_resources).to be_an(Array)
        expect(all_resources).to contain_exactly(
          'tasker.task',
          'tasker.workflow_step',
          'tasker.task_diagram',
          'tasker.health_status'
        )
      end
    end

    describe '.include?' do
      it 'returns true for defined resources' do
        expect(described_class::RESOURCES.include?('tasker.task')).to be(true)
        expect(described_class::RESOURCES.include?('tasker.workflow_step')).to be(true)
        expect(described_class::RESOURCES.include?('tasker.task_diagram')).to be(true)
      end

      it 'returns false for undefined resources' do
        expect(described_class::RESOURCES.include?('invalid.resource')).to be(false)
        expect(described_class::RESOURCES.include?('tasker.nonexistent')).to be(false)
        expect(described_class::RESOURCES.include?('')).to be(false)
      end
    end
  end

  describe 'ACTIONS module' do
    it 'defines expected action constants' do
      expect(described_class::ACTIONS::INDEX).to eq(:index)
      expect(described_class::ACTIONS::SHOW).to eq(:show)
      expect(described_class::ACTIONS::CREATE).to eq(:create)
      expect(described_class::ACTIONS::UPDATE).to eq(:update)
      expect(described_class::ACTIONS::DESTROY).to eq(:destroy)
      expect(described_class::ACTIONS::RETRY).to eq(:retry)
      expect(described_class::ACTIONS::CANCEL).to eq(:cancel)
    end

    describe '.crud' do
      it 'returns standard CRUD actions' do
        crud_actions = described_class::ACTIONS.crud

        expect(crud_actions).to be_an(Array)
        expect(crud_actions).to contain_exactly(:index, :show, :create, :update, :destroy)
      end
    end

    describe '.task_specific' do
      it 'returns task-specific actions' do
        task_actions = described_class::ACTIONS.task_specific

        expect(task_actions).to be_an(Array)
        expect(task_actions).to contain_exactly(:retry, :cancel)
      end
    end

    describe '.all' do
      it 'returns all action constants' do
        all_actions = described_class::ACTIONS.all

        expect(all_actions).to be_an(Array)
        expect(all_actions).to contain_exactly(
          :index, :show, :create, :update, :destroy, :retry, :cancel
        )
      end

      it 'includes both CRUD and task-specific actions' do
        all_actions = described_class::ACTIONS.all
        crud_actions = described_class::ACTIONS.crud
        task_actions = described_class::ACTIONS.task_specific

        expect(all_actions).to include(*crud_actions)
        expect(all_actions).to include(*task_actions)
      end
    end
  end

  describe 'constant consistency' do
    it 'has RESOURCES constants that match ResourceRegistry keys' do
      resource_registry_keys = Tasker::Authorization::ResourceRegistry.resources.keys
      resource_constants = described_class::RESOURCES.all

      expect(resource_constants).to match_array(resource_registry_keys)
    end

    it 'has ACTIONS constants used in ResourceRegistry' do
      all_actions_in_registry = Tasker::Authorization::ResourceRegistry.resources.values
                                                                       .flat_map { |config| config[:actions] }
                                                                       .uniq

      action_constants = described_class::ACTIONS.all

      # All actions in registry should be defined as constants
      all_actions_in_registry.each do |action|
        expect(action_constants).to include(action),
                                    "Action #{action} found in registry but not defined as constant"
      end
    end
  end

  describe 'immutability' do
    it 'does not allow modification of resource constants' do
      expect { described_class::RESOURCES::TASK << 'modified' }.to raise_error(FrozenError)
    end

    it 'does not allow modification of action constants' do
      # Symbols are immutable by nature, but let's test the arrays returned by methods
      expect { described_class::ACTIONS.all << :new_action }.not_to(change(described_class::ACTIONS, :all))
    end
  end
end
