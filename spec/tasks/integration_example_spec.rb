# frozen_string_literal: true

require 'rails_helper'
require_relative '../dummy/app/tasks/api_task/integration_example'
require_relative '../dummy/app/tasks/api_task/models/actions'

RSpec.describe ApiTask::IntegrationExample do
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:connection) { Faraday.new { |b| b.adapter(:test, stubs) } }
  let(:task_handler) do
    handler = described_class.new
    mock_connection = connection # Capture connection in closure
    original_get_step_handler = handler.method(:get_step_handler)
    handler.define_singleton_method(:get_step_handler) do |step|
      step_handler = original_get_step_handler.call(step)
      step_handler.instance_variable_set(:@connection, mock_connection)
      step_handler
    end
    handler
  end
  let(:cart_id) { 1 }
  let(:task_request) do
    Tasker::Types::TaskRequest.new(
      name: described_class::TASK_REGISTRY_NAME,
      context: { cart_id: cart_id },
      initiator: 'test',
      reason: 'Test API Integration',
      source_system: 'test'
    )
  end

  let(:factory) { Tasker::HandlerFactory.instance }
  let(:task) { task_handler.initialize_task!(task_request) }
  let(:step_sequence) { task_handler.get_sequence(task) }

  before do
    factory.register(described_class::TASK_REGISTRY_NAME, described_class)

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

  def complete_steps(step_names)
    step_names.each do |step_name|
      step = step_sequence.find_step_by_name(step_name)
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
    before do
      factory.register(described_class::TASK_REGISTRY_NAME, described_class)
    end

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
      invalid_request = Tasker::Types::TaskRequest.new(
        name: described_class::TASK_REGISTRY_NAME,
        context: {},
        initiator: 'test',
        reason: 'Test API Integration',
        source_system: 'test'
      )
      task = task_handler.initialize_task!(invalid_request)
      expect(task.errors[:context].first.to_s).to include("did not contain a required property of 'cart_id'")
    end
  end

  describe 'step execution' do
    before do
      factory.register(described_class::TASK_REGISTRY_NAME, described_class)
    end

    describe 'fetch_cart step' do
      it 'successfully fetches a valid cart' do
        step = step_sequence.find_step_by_name(described_class::STEP_FETCH_CART)
        task_handler.handle_one_step(task, step_sequence, step)
        expect(step.status).to eq(Tasker::Constants::WorkflowStepStatuses::COMPLETE)
        expect(step.results['cart']).to be_present
        expect(step.results['cart']['id']).to eq(cart_id)
      end

      it 'fails when cart is not found' do
        invalid_request = Tasker::Types::TaskRequest.new(
          name: described_class::TASK_REGISTRY_NAME,
          context: { cart_id: 999_999 },
          initiator: 'test',
          reason: 'Test API Integration',
          source_system: 'test'
        )
        task = task_handler.initialize_task!(invalid_request)
        step_sequence = task_handler.get_sequence(task)
        step = step_sequence.find_step_by_name(described_class::STEP_FETCH_CART)
        task_handler.handle_one_step(task, step_sequence, step)
        expect(step.status).to eq(Tasker::Constants::WorkflowStepStatuses::ERROR)
        expect(step.results['error']).to include('Cart not found')
      end
    end

    describe 'fetch_products step' do
      before do
        factory.register(described_class::TASK_REGISTRY_NAME, described_class)
      end

      it 'successfully fetches products' do
        step = step_sequence.find_step_by_name(described_class::STEP_FETCH_PRODUCTS)
        task_handler.handle_one_step(task, step_sequence, step)
        expect(step.status).to eq(Tasker::Constants::WorkflowStepStatuses::COMPLETE)
        expect(step.results['products']).to be_present
        expect(step.results['products']).to be_an(Array)
      end
    end

    describe 'validate_products step' do
      before do
        factory.register(described_class::TASK_REGISTRY_NAME, described_class)
      end

      it 'successfully validates products when all are in stock' do
        # First complete the prerequisite steps
        complete_steps([described_class::STEP_FETCH_CART, described_class::STEP_FETCH_PRODUCTS])

        # Then validate products
        validate_step = step_sequence.find_step_by_name(described_class::STEP_VALIDATE_PRODUCTS)
        task_handler.handle_one_step(task, step_sequence, validate_step)
        expect(validate_step.status).to eq(Tasker::Constants::WorkflowStepStatuses::COMPLETE)
        expect(validate_step.results['valid_products']).to be_present
      end
    end

    describe 'create_order step' do
      before do
        factory.register(described_class::TASK_REGISTRY_NAME, described_class)
      end

      it 'successfully creates an order from a valid cart' do
        # Complete prerequisite steps
        complete_steps([described_class::STEP_FETCH_CART, described_class::STEP_FETCH_PRODUCTS,
                        described_class::STEP_VALIDATE_PRODUCTS])

        # Create order
        create_order_step = step_sequence.find_step_by_name(described_class::STEP_CREATE_ORDER)
        task_handler.handle_one_step(task, step_sequence, create_order_step)

        log_step_results(create_order_step) unless create_order_step.complete?

        expect(create_order_step.status).to eq(Tasker::Constants::WorkflowStepStatuses::COMPLETE)
        expect(create_order_step.results['order_id']).to be_present
      end
    end

    describe 'publish_event step' do
      before do
        factory.register(described_class::TASK_REGISTRY_NAME, described_class)
      end

      it 'successfully publishes the order created event' do
        # Complete all prerequisite steps
        complete_steps(
          [
            described_class::STEP_FETCH_CART,
            described_class::STEP_FETCH_PRODUCTS,
            described_class::STEP_VALIDATE_PRODUCTS,
            described_class::STEP_CREATE_ORDER
          ]
        )

        # Publish event
        publish_step = step_sequence.find_step_by_name(described_class::STEP_PUBLISH_EVENT)
        task_handler.handle_one_step(task, step_sequence, publish_step)

        log_step_results(publish_step) unless publish_step.complete?

        expect(publish_step.status).to eq(Tasker::Constants::WorkflowStepStatuses::COMPLETE)
        expect(publish_step.results['published']).to be true
        expect(publish_step.results['publish_results']['status']).to eq('placed_pending_fulfillment')
      end
    end
  end

  describe 'complete workflow' do
    before do
      factory.register(described_class::TASK_REGISTRY_NAME, described_class)
    end

    it 'successfully completes the entire workflow' do
      task_handler.handle(task)
      expect(task.status).to eq(Tasker::Constants::TaskStatuses::COMPLETE)

      # Verify all steps are complete
      task.workflow_steps.each do |step|
        expect(step.status).to eq(Tasker::Constants::WorkflowStepStatuses::COMPLETE)
      end
    end
  end
end
