# frozen_string_literal: true

require 'rails_helper'
require_relative '../../mocks/configurable_failure_handlers'

RSpec.describe 'Complex Workflows Factory', type: :factory do
  before(:all) do
    # Register the complex workflow task handlers
    Tasker::HandlerFactory.instance.register('linear_workflow_task', LinearWorkflowTask)
    Tasker::HandlerFactory.instance.register('diamond_workflow_task', DiamondWorkflowTask)
    Tasker::HandlerFactory.instance.register('parallel_merge_workflow_task', ParallelMergeWorkflowTask)
    Tasker::HandlerFactory.instance.register('tree_workflow_task', TreeWorkflowTask)
    Tasker::HandlerFactory.instance.register('mixed_workflow_task', MixedWorkflowTask)
  end

  describe 'step template-based task handlers' do
    it 'creates linear workflow task with proper step templates' do
      task = create(:linear_workflow_task)

      expect(task).to be_persisted
      expect(task.named_task.name).to eq('linear_workflow_task')
      expect(task.context['workflow_type']).to eq('linear')
      expect(task.context['batch_id']).to be_present

      # Verify workflow steps are properly created with dependencies
      expect(task.workflow_steps.count).to eq(6)

      # Check that the root step is ready
      root_step = task.workflow_steps.find { |step| step.name == 'initialize_data' }
      expect(root_step.dependencies_satisfied?).to be true
      expect(root_step.ready?).to be true

      # Check that dependent steps are not ready yet
      dependent_step = task.workflow_steps.find { |step| step.name == 'validate_input' }
      expect(dependent_step.dependencies_satisfied?).to be false
      expect(dependent_step.ready?).to be false
    end

    it 'creates diamond workflow task with proper step templates' do
      task = create(:diamond_workflow_task)

      expect(task).to be_persisted
      expect(task.named_task.name).to eq('diamond_workflow_task')
      expect(task.context['workflow_type']).to eq('diamond')
    end

    it 'creates parallel merge workflow task' do
      task = create(:parallel_merge_workflow_task)

      expect(task).to be_persisted
      expect(task.named_task.name).to eq('parallel_merge_workflow_task')
    end

    it 'creates tree workflow task' do
      task = create(:tree_workflow_task)

      expect(task).to be_persisted
      expect(task.named_task.name).to eq('tree_workflow_task')
    end

    it 'creates mixed workflow task' do
      task = create(:mixed_workflow_task)

      expect(task).to be_persisted
      expect(task.named_task.name).to eq('mixed_workflow_task')
    end
  end

  describe 'complex workflow batch' do
    it 'creates a batch of mixed workflow types' do
      batch = build(:complex_workflow_batch, batch_size: 10)

      expect(batch[:tasks].size).to eq(10)
      expect(batch[:batch_id]).to be_present
      expect(batch[:total_count]).to eq(10)
      expect(batch[:pattern_counts].values.sum).to eq(10)

      # Verify all tasks have the same batch_id
      batch_ids = batch[:tasks].map { |task| task.context['batch_id'] }.uniq
      expect(batch_ids.size).to eq(1)
      expect(batch_ids.first).to eq(batch[:batch_id])
    end

    it 'respects pattern distribution' do
      batch = build(:complex_workflow_batch,
                    batch_size: 20,
                    pattern_distribution: { linear: 0.5, diamond: 0.5, parallel_merge: 0, tree: 0, mixed: 0 })

      expect(batch[:tasks].size).to eq(20)
      expect(batch[:pattern_counts][:linear]).to eq(10)
      expect(batch[:pattern_counts][:diamond]).to eq(10)
      expect(batch[:pattern_counts][:parallel_merge]).to eq(0)
    end
  end

  describe 'task handler step templates' do
    it 'LinearWorkflowTask has proper step dependencies' do
      handler = LinearWorkflowTask.new
      templates = handler.step_templates

      expect(templates.size).to eq(6)

      # Check linear dependency chain
      init_step = templates.find { |t| t.name == 'initialize_data' }
      validate_step = templates.find { |t| t.name == 'validate_input' }
      process_step = templates.find { |t| t.name == 'process_data' }

      expect(init_step.depends_on_step).to be_nil
      expect(validate_step.depends_on_step).to eq('initialize_data')
      expect(process_step.depends_on_step).to eq('validate_input')
    end

    it 'DiamondWorkflowTask has convergent dependencies' do
      handler = DiamondWorkflowTask.new
      templates = handler.step_templates

      merge_step = templates.find { |t| t.name == 'merge_branches' }
      expect(merge_step.depends_on_steps).to contain_exactly('branch_one_validate', 'branch_two_validate')
    end

    it 'MixedWorkflowTask has complex dependency patterns' do
      handler = MixedWorkflowTask.new
      templates = handler.step_templates

      # Check multiple dependencies
      begin_step = templates.find { |t| t.name == 'begin_processing' }
      expect(begin_step.depends_on_steps).to contain_exactly('validate_permissions', 'setup_environment')

      # Check final step dependencies
      final_step = templates.find { |t| t.name == 'finalize_and_report' }
      expect(final_step.depends_on_steps).to contain_exactly('process_critical_data', 'cleanup_temp_files')
    end
  end
end
