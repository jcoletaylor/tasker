# frozen_string_literal: true

require 'rails_helper'
require_relative '../../dummy/app/tasks/api_task/integration_example'

RSpec.describe Tasker::TaskDiagram do
  include FactoryWorkflowHelpers

  let(:cart_id) { 42 }
  let(:base_url) { 'https://example.com/api' }

  before do
    # Register the task handler for factory usage
    register_task_handler(ApiTask::IntegrationExample::TASK_REGISTRY_NAME, ApiTask::IntegrationExample)
  end

  describe '#to_mermaid' do
    let(:unique_reason) { "mermaid_test_#{SecureRandom.hex(8)}" }
    let(:task) do
      create_api_integration_workflow(
        cart_id: cart_id,
        reason: unique_reason,
        with_dependencies: true
      )
    end
    let(:diagram) { described_class.new(task, base_url) }

    subject(:mermaid_output) { diagram.to_mermaid }

    it 'generates valid mermaid flowchart syntax' do
      expect(mermaid_output).to start_with('graph TD')
      expect(mermaid_output).to include("task_#{task.task_id}")
    end

    it 'includes all workflow steps in the diagram' do
      task.workflow_steps.each do |step|
        expect(mermaid_output).to include("step_#{step.workflow_step_id}")
      end
    end

    it 'applies correct styling for pending steps' do
      task.workflow_steps.each do |step|
        expect(mermaid_output).to include("style step_#{step.workflow_step_id} fill:lightblue;")
      end
    end

    it 'includes clickable URLs when base_url is provided' do
      task.workflow_steps.each do |step|
        expected_url = "#{base_url}/tasks/#{task.task_id}/workflow_steps/#{step.workflow_step_id}"
        expect(mermaid_output).to include("click step_#{step.workflow_step_id} \"#{expected_url}\"")
      end
    end

    context 'with steps in error state' do
      let(:error_reason) { "error_diagram_test_#{SecureRandom.hex(8)}" }
      let(:failed_task) do
        create_api_integration_workflow(
          cart_id: cart_id + 100,
          reason: error_reason,
          with_dependencies: true
        )
      end
      let(:failed_diagram) { described_class.new(failed_task, base_url) }

      before do
        # Set first two steps to error state and capture which ones we set
        @error_steps = failed_task.workflow_steps.limit(2).to_a
        @error_steps.each do |step|
          set_step_to_error(step, 'Simulated error for diagram testing')
        end
      end

      it 'applies error styling to failed steps' do
        error_output = failed_diagram.to_mermaid

        @error_steps.each do |step|
          expect(error_output).to include("style step_#{step.workflow_step_id} fill:red;")
        end
      end
    end

    context 'with DAG structure validation' do
      it 'includes task node connections' do
        expect(mermaid_output).to include("task_#{task.task_id}")
      end

      it 'represents workflow step dependencies correctly' do
        # The integration example creates a DAG structure where:
        # - Root steps connect to task
        # - Dependencies flow through the workflow
        # This is a basic structural check
        task.workflow_steps.each do |step|
          expect(mermaid_output).to include("step_#{step.workflow_step_id}")
        end
      end
    end
  end

  describe '#to_html' do
    let(:html_reason) { "html_test_#{SecureRandom.hex(8)}" }
    let(:task) do
      create_api_integration_workflow(
        cart_id: cart_id + 200,
        reason: html_reason,
        with_dependencies: true
      )
    end
    let(:diagram) { described_class.new(task, base_url) }

    subject(:html_output) { diagram.to_html }

    it 'generates a complete HTML document' do
      expect(html_output).to include('<!DOCTYPE html>', '<html>', '<head>', '<body>')
    end

    it 'embeds the mermaid diagram' do
      expect(html_output).to include('<div class="tasker-diagram mermaid">')
      expect(html_output).to include(diagram.to_mermaid)
    end

    it 'includes task metadata in the HTML' do
      expect(html_output).to include("Task ID: #{task.task_id}")
      expect(html_output).to include("Task Name: #{task.named_task.name}")
      expect(html_output).to include("Status: #{task.state_machine.current_state}")
    end
  end

  describe 'diagram component building' do
    let(:component_reason) { "component_test_#{SecureRandom.hex(8)}" }
    let(:task) do
      create_api_integration_workflow(
        cart_id: cart_id + 300,
        reason: component_reason,
        with_dependencies: true
      )
    end
    let(:diagram) { described_class.new(task, base_url) }

    describe 'task node creation' do
      subject(:task_node) { diagram.send(:build_task_node) }

      it 'creates a proper task node' do
        expect(task_node).to be_a(Tasker::Diagram::Node)
        expect(task_node.id).to eq("task_#{task.task_id}")
        expect(task_node.label).to include(task.named_task.name)
      end
    end

    describe 'workflow step node creation' do
      let(:sample_step) { task.workflow_steps.first }
      subject(:step_node) { diagram.send(:build_step_node, sample_step) }

      before do
        skip 'No workflow steps available for testing' if sample_step.nil?
      end

      it 'creates a proper step node' do
        expect(step_node).to be_a(Tasker::Diagram::Node)
        expect(step_node.id).to eq("step_#{sample_step.workflow_step_id}")
        expect(step_node.label).to include(sample_step.named_step.name)
      end

      it 'applies correct styling for pending steps' do
        expect(step_node.style).to include('fill:lightblue')
      end

      it 'includes the correct URL' do
        expected_url = "#{base_url}/tasks/#{task.task_id}/workflow_steps/#{sample_step.workflow_step_id}"
        expect(step_node.url).to eq(expected_url)
      end
    end

    describe 'edge creation' do
      subject(:edge) { diagram.send(:build_edge, 'source_id', 'target_id', 'edge_label') }

      it 'creates a proper edge object' do
        expect(edge).to be_a(Tasker::Diagram::Edge)
        expect(edge.source_id).to eq('source_id')
        expect(edge.target_id).to eq('target_id')
        expect(edge.label).to eq('edge_label')
      end
    end
  end
end
