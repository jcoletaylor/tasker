# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Authorization::ResourceRegistry do
  # Create shorter aliases for constants to make tests more readable
  RESOURCES = Tasker::Authorization::ResourceConstants::RESOURCES
  ACTIONS = Tasker::Authorization::ResourceConstants::ACTIONS

  describe '.resources' do
    it 'returns the frozen resource registry' do
      resources = described_class.resources

      expect(resources).to be_a(Hash)
      expect(resources).to be_frozen
      expect(resources.keys).to include(RESOURCES::TASK, RESOURCES::WORKFLOW_STEP, RESOURCES::TASK_DIAGRAM)
    end

    it 'contains expected structure for each resource' do
      resources = described_class.resources

      resources.each_value do |config|
        expect(config).to have_key(:actions)
        expect(config).to have_key(:description)
        expect(config[:actions]).to be_an(Array)
        expect(config[:description]).to be_a(String)
      end
    end
  end

  describe '.resource_exists?' do
    it 'returns true for existing resources' do
      expect(described_class.resource_exists?(RESOURCES::TASK)).to be(true)
      expect(described_class.resource_exists?(RESOURCES::WORKFLOW_STEP)).to be(true)
      expect(described_class.resource_exists?(RESOURCES::TASK_DIAGRAM)).to be(true)
    end

    it 'returns false for non-existing resources' do
      expect(described_class.resource_exists?('invalid.resource')).to be(false)
      expect(described_class.resource_exists?('tasker.nonexistent')).to be(false)
      expect(described_class.resource_exists?('')).to be(false)
    end
  end

  describe '.action_exists?' do
    context 'with valid resource' do
      it 'returns true for valid actions' do
        expect(described_class.action_exists?(RESOURCES::TASK, ACTIONS::INDEX)).to be(true)
        expect(described_class.action_exists?(RESOURCES::TASK, ACTIONS::SHOW)).to be(true)
        expect(described_class.action_exists?(RESOURCES::TASK, ACTIONS::CREATE)).to be(true)
        expect(described_class.action_exists?(RESOURCES::TASK, ACTIONS::UPDATE)).to be(true)
        expect(described_class.action_exists?(RESOURCES::TASK, ACTIONS::DESTROY)).to be(true)
        expect(described_class.action_exists?(RESOURCES::TASK, ACTIONS::RETRY)).to be(true)
        expect(described_class.action_exists?(RESOURCES::TASK, ACTIONS::CANCEL)).to be(true)
      end

      it 'returns true for string actions' do
        expect(described_class.action_exists?(RESOURCES::TASK, 'index')).to be(true)
        expect(described_class.action_exists?(RESOURCES::TASK, 'show')).to be(true)
      end

      it 'returns false for invalid actions' do
        expect(described_class.action_exists?(RESOURCES::TASK, :invalid)).to be(false)
        expect(described_class.action_exists?(RESOURCES::TASK, :nonexistent)).to be(false)
      end
    end

    context 'with invalid resource' do
      it 'returns false for any action' do
        expect(described_class.action_exists?('invalid.resource', :index)).to be(false)
        expect(described_class.action_exists?('tasker.nonexistent', :show)).to be(false)
      end
    end

    context 'with workflow_step resource' do
      it 'returns true for valid workflow step actions' do
        expect(described_class.action_exists?(RESOURCES::WORKFLOW_STEP, ACTIONS::INDEX)).to be(true)
        expect(described_class.action_exists?(RESOURCES::WORKFLOW_STEP, ACTIONS::SHOW)).to be(true)
        expect(described_class.action_exists?(RESOURCES::WORKFLOW_STEP, ACTIONS::UPDATE)).to be(true)
        expect(described_class.action_exists?(RESOURCES::WORKFLOW_STEP, ACTIONS::RETRY)).to be(true)
        expect(described_class.action_exists?(RESOURCES::WORKFLOW_STEP, ACTIONS::CANCEL)).to be(true)
      end

      it 'returns true for destroy action (now available to workflow steps)' do
        expect(described_class.action_exists?(RESOURCES::WORKFLOW_STEP, ACTIONS::DESTROY)).to be(true)
      end

      it 'returns false for actions not available to workflow steps' do
        expect(described_class.action_exists?(RESOURCES::WORKFLOW_STEP, ACTIONS::CREATE)).to be(false)
      end
    end

    context 'with task_diagram resource' do
      it 'returns true for index and show actions' do
        expect(described_class.action_exists?(RESOURCES::TASK_DIAGRAM, ACTIONS::INDEX)).to be(true)
        expect(described_class.action_exists?(RESOURCES::TASK_DIAGRAM, ACTIONS::SHOW)).to be(true)
      end

      it 'returns false for other actions' do
        expect(described_class.action_exists?(RESOURCES::TASK_DIAGRAM, ACTIONS::CREATE)).to be(false)
        expect(described_class.action_exists?(RESOURCES::TASK_DIAGRAM, ACTIONS::UPDATE)).to be(false)
        expect(described_class.action_exists?(RESOURCES::TASK_DIAGRAM, ACTIONS::DESTROY)).to be(false)
      end
    end
  end

  describe '.all_permissions' do
    it 'returns all permissions in resource:action format' do
      permissions = described_class.all_permissions

      expect(permissions).to be_an(Array)
      expect(permissions).to include("#{RESOURCES::TASK}:index", "#{RESOURCES::TASK}:show", "#{RESOURCES::TASK}:create")
      expect(permissions).to include("#{RESOURCES::WORKFLOW_STEP}:index", "#{RESOURCES::WORKFLOW_STEP}:show")
      expect(permissions).to include("#{RESOURCES::TASK_DIAGRAM}:show")
    end

    it 'returns permissions for all defined resources' do
      permissions = described_class.all_permissions
      expected_count = described_class.resources.sum { |_, config| config[:actions].size }

      expect(permissions.size).to eq(expected_count)
    end

    it 'contains only valid permission strings' do
      permissions = described_class.all_permissions

      permissions.each do |permission|
        expect(permission).to match(/\A[\w.]+:[\w]+\z/)
        resource, action = permission.split(':')
        expect(described_class.resource_exists?(resource)).to be(true)
        expect(described_class.action_exists?(resource, action.to_sym)).to be(true)
      end
    end
  end

  describe '.actions_for_resource' do
    it 'returns actions for existing resources' do
      task_actions = described_class.actions_for_resource(RESOURCES::TASK)
      expect(task_actions).to eq([ACTIONS::INDEX, ACTIONS::SHOW, ACTIONS::CREATE, ACTIONS::UPDATE, ACTIONS::DESTROY,
                                  ACTIONS::RETRY, ACTIONS::CANCEL])

      step_actions = described_class.actions_for_resource(RESOURCES::WORKFLOW_STEP)
      expect(step_actions).to eq([ACTIONS::INDEX, ACTIONS::SHOW, ACTIONS::UPDATE, ACTIONS::DESTROY, ACTIONS::RETRY,
                                  ACTIONS::CANCEL])

      diagram_actions = described_class.actions_for_resource(RESOURCES::TASK_DIAGRAM)
      expect(diagram_actions).to eq([ACTIONS::INDEX, ACTIONS::SHOW])
    end

    it 'returns empty array for non-existing resources' do
      expect(described_class.actions_for_resource('invalid.resource')).to eq([])
      expect(described_class.actions_for_resource('tasker.nonexistent')).to eq([])
    end
  end

  describe '.resource_description' do
    it 'returns descriptions for existing resources' do
      expect(described_class.resource_description(RESOURCES::TASK)).to eq('Tasker workflow tasks')
      expect(described_class.resource_description(RESOURCES::WORKFLOW_STEP)).to eq('Individual workflow steps')
      expect(described_class.resource_description(RESOURCES::TASK_DIAGRAM)).to eq('Task workflow diagrams')
    end

    it 'returns nil for non-existing resources' do
      expect(described_class.resource_description('invalid.resource')).to be_nil
      expect(described_class.resource_description('tasker.nonexistent')).to be_nil
    end
  end
end
