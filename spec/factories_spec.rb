# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'FactoryBot factories', type: :model do
  describe 'basic factory creation' do
    it 'creates a valid dependent_system' do
      system = create(:dependent_system)
      expect(system).to be_valid
      expect(system.name).to be_present
      expect(system.description).to be_present
    end

    it 'creates a valid named_task' do
      task = create(:named_task)
      expect(task).to be_valid
      expect(task.name).to be_present
      expect(task.description).to be_present
    end

    it 'creates a valid named_step' do
      step = create(:named_step)
      expect(step).to be_valid
      expect(step.name).to be_present
      expect(step.description).to be_present
      expect(step.dependent_system).to be_present
    end

    it 'creates a valid task' do
      task = create(:task)
      expect(task).to be_valid
      expect(task.named_task).to be_present
      expect(task.context).to be_present
      expect(task.initiator).to be_present
      expect(task.source_system).to be_present
      expect(task.reason).to be_present
    end

    it 'creates a valid workflow_step' do
      step = create(:workflow_step)
      expect(step).to be_valid
      expect(step.task).to be_present
      expect(step.named_step).to be_present
      expect(step.status).to eq(Tasker::Constants::WorkflowStepStatuses::PENDING)
    end
  end

  describe 'factory traits' do
    it 'creates dependent_system with api_system trait' do
      system = create(:dependent_system, :api_system)
      expect(system.name).to eq('api')
      expect(system.description).to include('API integration')
    end

    it 'creates named_task with api_integration trait' do
      task = create(:named_task, :api_integration)
      expect(task.name).to eq('api_integration_example')
      expect(task.description).to include('API integration')
    end

    it 'creates named_step with fetch_cart trait' do
      step = create(:named_step, :fetch_cart)
      expect(step.name).to eq('fetch_cart')
      expect(step.dependent_system.name).to eq('api')
    end

    it 'creates task with api_integration trait' do
      task = create(:task, :api_integration)
      expect(task.named_task.name).to eq('api_integration_example')
      expect(task.context).to have_key('cart_id')
    end

    it 'creates workflow_step with complete trait' do
      step = create(:workflow_step, :complete)
      expect(step.status).to eq(Tasker::Constants::WorkflowStepStatuses::COMPLETE)
      expect(step.processed).to be true
      expect(step.results).to have_key('success')
    end
  end

  describe 'state machine transition factories' do
    it 'creates a valid task_transition' do
      transition = create(:task_transition)
      expect(transition).to be_valid
      expect(transition.task).to be_present
      expect(transition.to_state).to eq(Tasker::Constants::TaskStatuses::PENDING)
      expect(transition.sort_key).to eq(0)
    end

    it 'creates a valid workflow_step_transition' do
      transition = create(:workflow_step_transition)
      expect(transition).to be_valid
      expect(transition.workflow_step).to be_present
      expect(transition.to_state).to eq(Tasker::Constants::WorkflowStepStatuses::PENDING)
      expect(transition.sort_key).to eq(0)
    end

    it 'creates task_transition with complete_transition trait' do
      transition = create(:task_transition, :complete_transition)
      expect(transition.to_state).to eq(Tasker::Constants::TaskStatuses::COMPLETE)
      expect(transition.metadata).to have_key('triggered_by')
    end

    it 'creates workflow_step_transition with start_execution trait' do
      transition = create(:workflow_step_transition, :start_execution)
      expect(transition.to_state).to eq(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
      expect(transition.metadata).to have_key('triggered_by')
    end
  end

  describe 'edge relationship factories' do
    it 'creates a valid workflow_step_edge' do
      edge = create(:workflow_step_edge)
      expect(edge).to be_valid
      expect(edge.from_step).to be_present
      expect(edge.to_step).to be_present
      expect(edge.name).to eq('provides')
      # Both steps should belong to the same task
      expect(edge.from_step.task).to eq(edge.to_step.task)
    end

    it 'creates workflow_step_edge with cart_to_validation trait' do
      edge = create(:workflow_step_edge, :cart_to_validation)
      expect(edge.from_step.named_step.name).to eq('fetch_cart')
      expect(edge.to_step.named_step.name).to eq('validate_products')
      expect(edge.name).to eq('provides')
    end
  end

  describe 'composite workflow factories' do
    it 'creates api_integration_workflow with all dependencies' do
      workflow = create(:api_integration_workflow)
      expect(workflow).to be_valid
      expect(workflow.named_task.name).to eq('api_integration_example')
      expect(workflow.workflow_steps.count).to eq(5)

      # Check step names using includes instead of joins
      step_names = workflow.workflow_steps.includes(:named_step).map { |step| step.named_step.name }
      expect(step_names).to contain_exactly(
        'fetch_cart', 'fetch_products', 'validate_products', 'create_order', 'publish_event'
      )

      # Check dependencies exist - use correct association name
      expect(Tasker::WorkflowStepEdge.where(from_step: workflow.workflow_steps).count).to eq(4)
    end

    it 'creates simple_linear_workflow' do
      workflow = create(:simple_linear_workflow, step_count: 3)
      expect(workflow).to be_valid
      expect(workflow.workflow_steps.count).to eq(3)
      # Check dependencies using correct association
      expect(Tasker::WorkflowStepEdge.where(from_step: workflow.workflow_steps).count).to eq(2)
    end

    it 'creates parallel_workflow' do
      workflow = create(:parallel_workflow, parallel_count: 3)
      expect(workflow).to be_valid
      # Should have: 1 init + 3 parallel + 1 final = 5 steps
      expect(workflow.workflow_steps.count).to eq(5)
      # Should have: 3 init->parallel + 3 parallel->final = 6 edges
      expect(Tasker::WorkflowStepEdge.where(from_step: workflow.workflow_steps).count).to eq(6)
    end

    it 'creates task_with_transitions' do
      task = create(:task_with_transitions, :completed_with_transitions)
      expect(task).to be_valid
      expect(task.task_transitions.count).to eq(3) # Full transition sequence: pending → in_progress → complete
      expect(task.status).to eq(Tasker::Constants::TaskStatuses::COMPLETE)
    end

    it 'creates step_with_transitions' do
      step = create(:step_with_transitions, :successful_with_transitions)
      expect(step).to be_valid
      expect(step.workflow_step_transitions.count).to eq(3) # Full transition sequence: pending → in_progress → complete
      expect(step.status).to eq(Tasker::Constants::WorkflowStepStatuses::COMPLETE)
    end
  end

  describe 'factory sequences and uniqueness' do
    it 'creates multiple dependent_systems with unique names' do
      system1 = create(:dependent_system)
      system2 = create(:dependent_system)
      expect(system1.name).not_to eq(system2.name)
    end

    it 'creates multiple named_tasks with unique names' do
      task1 = create(:named_task)
      task2 = create(:named_task)
      expect(task1.name).not_to eq(task2.name)
    end

    it 'creates multiple named_steps with unique names' do
      step1 = create(:named_step)
      step2 = create(:named_step)
      expect(step1.name).not_to eq(step2.name)
    end
  end

  describe 'factory associations' do
    it 'properly associates workflow_step with task and named_step' do
      step = create(:workflow_step)
      expect(step.task).to be_persisted
      expect(step.named_step).to be_persisted
      expect(step.task.named_task).to be_persisted
    end

    it 'properly associates transitions with their parent objects' do
      task_transition = create(:task_transition)
      step_transition = create(:workflow_step_transition)

      expect(task_transition.task).to be_persisted
      expect(step_transition.workflow_step).to be_persisted
      expect(step_transition.workflow_step.task).to be_persisted
    end
  end
end
