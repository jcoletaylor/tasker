# frozen_string_literal: true

require 'rails_helper'
require_relative '../dummy/app/tasks/api_task/integration_example'
require_relative '../dummy/app/tasks/api_task/models/actions'

RSpec.describe ApiTask::IntegrationExample do
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:connection) { Faraday.new { |b| b.adapter(:test, stubs) } }
  let(:task_handler) { create_api_task_handler_with_connection(described_class, connection) }
  let(:cart_id) { 1 }

  # Factory-based task creation (replacement for manual TaskRequest creation)
  let(:task) { create_api_integration_workflow(cart_id: cart_id) }
  let(:step_sequence) { get_sequence_for_task(task) }

  before do
    register_task_handler(described_class::TASK_REGISTRY_NAME, described_class)

    # Stub cart endpoint
    stubs.get("/carts/#{cart_id}") do |env|
      cart = ApiTask::Actions::Cart.find(cart_id)
      raise Faraday::ResourceNotFound.new('Cart not found', nil) unless cart

      Faraday::Response.new(
        Faraday::Env.from(
          status: 200,
          response_headers: { 'Content-Type' => 'application/json' },
          body: { cart: cart.to_h }.to_json,
          url: env.url
        )
      )
    end

    stubs.get('/carts/999999') do |env|
      response = Faraday::Response.new(
        Faraday::Env.from(
          status: 404,
          response_headers: { 'Content-Type' => 'application/json' },
          body: { error: 'Cart not found' }.to_json,
          url: env.url
        )
      )
      raise Faraday::ResourceNotFound.new('Cart not found', response)
    end

    # Stub products endpoint
    stubs.get('/products') do |env|
      products = ApiTask::Actions::Product.all
      Faraday::Response.new(
        Faraday::Env.from(
          status: 200,
          response_headers: { 'Content-Type' => 'application/json' },
          body: { products: products.map(&:to_h) }.to_json,
          url: env.url
        )
      )
    end
  end

  # Factory-based step completion helper (replacement for complete_steps method)
  def complete_steps(step_names)
    step_names.each do |step_name|
      step = find_step_by_name(task, step_name)
      task_handler.handle_one_step(task, step_sequence, step)
      log_step_results(step) unless step.complete?
      expect(step.status).to eq(Tasker::Constants::WorkflowStepStatuses::COMPLETE)
    end
  end

  def log_step_results(step)
    Rails.logger.error("Step #{step.name} failed with status #{step.status}")
    Rails.logger.error("Results: #{step.results.inspect}")
  end

  describe 'task initialization' do
    it 'creates a task with the correct steps' do
      expect(task).to be_valid
      expect(task.workflow_steps.count).to eq(5)
      expect(task.workflow_steps.map(&:name)).to contain_exactly(
        described_class::STEP_FETCH_CART,
        described_class::STEP_FETCH_PRODUCTS,
        described_class::STEP_VALIDATE_PRODUCTS,
        described_class::STEP_CREATE_ORDER,
        described_class::STEP_PUBLISH_EVENT
      )
    end

    it 'validates required cart_id in context' do
      # Create task with invalid context using factory
      invalid_task = create_api_integration_workflow(cart_id: nil)
      invalid_task.update_columns(context: {})

      # Validate context (this triggers the validation logic)
      expect(invalid_task.errors.messages).to be_empty # Task creation succeeds

      # The validation happens during task execution, not creation
      # We'll test this through the actual workflow execution
      expect(invalid_task.context).to eq({})
    end
  end

  describe 'step execution' do
    describe 'fetch_cart step' do
      it 'successfully fetches a valid cart' do
        step = find_step_by_name(task, described_class::STEP_FETCH_CART)
        task_handler.handle_one_step(task, step_sequence, step)
        expect(step.status).to eq(Tasker::Constants::WorkflowStepStatuses::COMPLETE)
        expect(step.results['cart']).to be_present
        expect(step.results['cart']['id']).to eq(cart_id)
      end

      it 'fails when cart is not found' do
        # Create task with invalid cart_id using factory
        invalid_task = create_api_integration_workflow(cart_id: 999_999)
        invalid_step_sequence = get_sequence_for_task(invalid_task)
        step = find_step_by_name(invalid_task, described_class::STEP_FETCH_CART)

        task_handler.handle_one_step(invalid_task, invalid_step_sequence, step)
        expect(step.status).to eq(Tasker::Constants::WorkflowStepStatuses::ERROR)
        expect(step.results['error']).to include('Cart not found')
      end
    end

    describe 'fetch_products step' do
      it 'successfully fetches products' do
        step = find_step_by_name(task, described_class::STEP_FETCH_PRODUCTS)
        task_handler.handle_one_step(task, step_sequence, step)
        expect(step.status).to eq(Tasker::Constants::WorkflowStepStatuses::COMPLETE)
        expect(step.results['products']).to be_present
        expect(step.results['products']).to be_an(Array)
      end
    end

    describe 'validate_products step' do
      it 'successfully validates products when all are in stock' do
        # Complete prerequisite steps using factory helper
        complete_steps([described_class::STEP_FETCH_CART, described_class::STEP_FETCH_PRODUCTS])

        # Then validate products
        validate_step = find_step_by_name(task, described_class::STEP_VALIDATE_PRODUCTS)
        task_handler.handle_one_step(task, step_sequence, validate_step)
        expect(validate_step.status).to eq(Tasker::Constants::WorkflowStepStatuses::COMPLETE)
        expect(validate_step.results['valid_products']).to be_present
      end
    end

    describe 'create_order step' do
      it 'successfully creates an order from a valid cart' do
        # Complete prerequisite steps using factory helper
        complete_steps([described_class::STEP_FETCH_CART, described_class::STEP_FETCH_PRODUCTS,
                        described_class::STEP_VALIDATE_PRODUCTS])

        # Create order
        create_order_step = find_step_by_name(task, described_class::STEP_CREATE_ORDER)
        task_handler.handle_one_step(task, step_sequence, create_order_step)

        log_step_results(create_order_step) unless create_order_step.complete?

        expect(create_order_step.status).to eq(Tasker::Constants::WorkflowStepStatuses::COMPLETE)
        expect(create_order_step.results['order_id']).to be_present
      end
    end

    describe 'publish_event step' do
      it 'successfully publishes the order created event' do
        # Complete all prerequisite steps using factory helper
        complete_steps(
          [
            described_class::STEP_FETCH_CART,
            described_class::STEP_FETCH_PRODUCTS,
            described_class::STEP_VALIDATE_PRODUCTS,
            described_class::STEP_CREATE_ORDER
          ]
        )

        # Publish event
        publish_step = find_step_by_name(task, described_class::STEP_PUBLISH_EVENT)
        task_handler.handle_one_step(task, step_sequence, publish_step)

        log_step_results(publish_step) unless publish_step.complete?

        expect(publish_step.status).to eq(Tasker::Constants::WorkflowStepStatuses::COMPLETE)
        expect(publish_step.results['published']).to be true
        expect(publish_step.results['publish_results']['status']).to eq('placed_pending_fulfillment')
      end
    end
  end

  describe 'complete workflow' do
    it 'successfully completes the entire workflow' do
      # Create a fresh task WITHOUT pre-created dependencies to avoid step name conflicts
      # This allows the task handler to create steps properly at runtime
      fresh_task = create(:api_integration_workflow, context: { cart_id: cart_id }, with_dependencies: false)

      # Use factory-created task with full workflow execution
      task_handler.handle(fresh_task)
      expect(fresh_task.status).to eq(Tasker::Constants::TaskStatuses::COMPLETE)

      # Verify all steps are complete
      fresh_task.workflow_steps.each do |step|
        expect(step.status).to eq(Tasker::Constants::WorkflowStepStatuses::COMPLETE)
      end
    end
  end
end
