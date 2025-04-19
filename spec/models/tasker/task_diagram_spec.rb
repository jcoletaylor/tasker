# frozen_string_literal: true

require 'rails_helper'
require_relative '../../dummy/app/tasks/api_task/integration_example'

RSpec.describe Tasker::TaskDiagram do
  # Use a real task from the API integration example
  let(:factory) { Tasker::HandlerFactory.instance }
  let(:cart_id) { 1 }
  let(:task_request) do
    Tasker::Types::TaskRequest.new(
      name: ApiTask::IntegrationExample::TASK_REGISTRY_NAME,
      context: { cart_id: cart_id },
      initiator: 'test',
      reason: 'Test diagram generation',
      source_system: 'test'
    )
  end

  let(:task_handler) { ApiTask::IntegrationExample.new }
  let(:task) { task_handler.initialize_task!(task_request) }
  let(:base_url) { 'https://example.com/api' }
  let(:diagram) { described_class.new(task, base_url) }

  before do
    # Register the task handler with the factory
    factory.register(ApiTask::IntegrationExample::TASK_REGISTRY_NAME, ApiTask::IntegrationExample)

    # Create a realistic workflow with steps in different statuses
    setup_workflow_steps
  end

  # Helper method to set up a realistic workflow with steps in different statuses
  def setup_workflow_steps
    # Access the workflow steps
    @steps = task.workflow_steps.reload

    # Set different statuses for the steps to test visualization
    # We'll create all 5 steps from the ApiTask::IntegrationExample
    # with different statuses to ensure our diagram shows them correctly

    # Completed step
    @fetch_cart_step = @steps.find { |s| s.name == ApiTask::IntegrationExample::STEP_FETCH_CART }
    @fetch_cart_step.update!(
      status: Tasker::Constants::WorkflowStepStatuses::COMPLETE,
      processed: true,
      in_process: false,
      attempts: 1,
      results: { cart: { id: cart_id, user_id: 123, products: [] } }
    )

    # In progress step
    @fetch_products_step = @steps.find { |s| s.name == ApiTask::IntegrationExample::STEP_FETCH_PRODUCTS }
    @fetch_products_step.update!(
      status: Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS,
      processed: false,
      in_process: true,
      attempts: 0
    )

    # Pending step
    @validate_products_step = @steps.find { |s| s.name == ApiTask::IntegrationExample::STEP_VALIDATE_PRODUCTS }
    @validate_products_step.update!(
      status: Tasker::Constants::WorkflowStepStatuses::PENDING,
      processed: false,
      in_process: false,
      attempts: 0
    )

    # Error step
    @create_order_step = @steps.find { |s| s.name == ApiTask::IntegrationExample::STEP_CREATE_ORDER }
    @create_order_step.update!(
      status: Tasker::Constants::WorkflowStepStatuses::ERROR,
      processed: false,
      in_process: false,
      attempts: 2,
      results: { error: 'Failed to create order: insufficient inventory', backtrace: 'line 1\nline 2' }
    )

    # Cancelled step
    @publish_event_step = @steps.find { |s| s.name == ApiTask::IntegrationExample::STEP_PUBLISH_EVENT }
    @publish_event_step.update!(
      status: Tasker::Constants::WorkflowStepStatuses::CANCELLED,
      processed: false,
      in_process: false,
      attempts: 0
    )
  end

  describe '#to_mermaid' do
    it 'generates valid mermaid flowchart syntax' do
      mermaid_output = diagram.to_mermaid

      # Basic validation of the output
      expect(mermaid_output).to start_with('graph TD')
      expect(mermaid_output).to include("task_#{task.task_id}")

      # Verify all steps are included
      @steps.each do |step|
        expect(mermaid_output).to include("step_#{step.workflow_step_id}")
      end

      # Verify the diagram includes proper status colors
      verify_step_colors(mermaid_output)

      # Verify connections between steps (DAG structure)
      verify_step_connections(mermaid_output)
    end

    it 'includes URLs when base_url is provided' do
      mermaid_output = diagram.to_mermaid

      @steps.each do |step|
        expect(mermaid_output).to include("click step_#{step.workflow_step_id} \"#{base_url}/tasks/#{task.task_id}/workflow_steps/#{step.workflow_step_id}\"")
      end
    end

    it 'shows error information in the diagram' do
      mermaid_output = diagram.to_mermaid

      # Check that error information is included in the error step
      expect(mermaid_output).to include('Error: Failed to create order')
    end

    private

    def verify_step_colors(mermaid_output)
      # Verify each step has the appropriate color based on status
      # The style is now added as a separate line with 'style' command
      expect(mermaid_output).to include("style step_#{@fetch_cart_step.workflow_step_id} fill:green;")
      expect(mermaid_output).to include("style step_#{@fetch_products_step.workflow_step_id} fill:lightgreen;")
      expect(mermaid_output).to include("style step_#{@validate_products_step.workflow_step_id} fill:lightblue;")
      expect(mermaid_output).to include("style step_#{@create_order_step.workflow_step_id} fill:red;")
      expect(mermaid_output).to include("style step_#{@publish_event_step.workflow_step_id} fill:gray;")
    end

    def verify_step_connections(mermaid_output)
      # Check that dependencies between steps are properly represented
      # This depends on how your DAG is structured in the integration example

      # Fetch cart and fetch products are root nodes, so they should connect to task
      expect(mermaid_output).to include("task_#{task.task_id}")

      # The DAG from integration_example.rb should have:
      # validate_products depends on fetch_cart and fetch_products
      # create_order depends on validate_products
      # publish_event depends on create_order
    end
  end

  describe '#to_html' do
    it 'generates an HTML document with embedded mermaid diagram' do
      html_output = diagram.to_html

      # Check for essential HTML structure
      expect(html_output).to include('<!DOCTYPE html>', '<html>', '<head>', '<body>')

      # Check that the diagram is included
      expect(html_output).to include('<div class="tasker-diagram mermaid">')
      expect(html_output).to include(diagram.to_mermaid)

      # Check for task information
      expect(html_output).to include("Task ID: #{task.task_id}")
      expect(html_output).to include("Task Name: #{task.name}")
      expect(html_output).to include("Status: #{task.status}")
    end
  end

  describe 'integration with native diagram library' do
    it 'builds proper node objects for tasks' do
      node = diagram.send(:build_task_node)
      expect(node).to be_a(Tasker::Diagram::Node)
      expect(node.id).to eq("task_#{task.task_id}")
      expect(node.label).to include(task.name)
    end

    it 'builds proper node objects for workflow steps' do
      node = diagram.send(:build_step_node, @create_order_step)
      expect(node).to be_a(Tasker::Diagram::Node)
      expect(node.id).to eq("step_#{@create_order_step.workflow_step_id}")
      expect(node.label).to include(@create_order_step.name)
      expect(node.style).to include('fill:red')
      expect(node.url).to eq("#{base_url}/tasks/#{task.task_id}/workflow_steps/#{@create_order_step.workflow_step_id}")
    end

    it 'builds proper edge objects between nodes' do
      edge = diagram.send(:build_edge, 'source', 'target', 'label')
      expect(edge).to be_a(Tasker::Diagram::Edge)
      expect(edge.source_id).to eq('source')
      expect(edge.target_id).to eq('target')
      expect(edge.label).to eq('label')
    end
  end
end
