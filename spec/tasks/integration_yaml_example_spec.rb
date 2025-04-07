# frozen_string_literal: true

require 'rails_helper'
require_relative '../dummy/app/tasks/api_task/integration_yaml_example'
require_relative '../dummy/app/tasks/api_task/models/actions'

RSpec.describe ApiTask::IntegrationYamlExample do
  let(:yaml_path) { described_class.yaml_path }
  let(:yaml_config) { YAML.load_file(yaml_path) }
  let(:handler_class) { described_class }
  let(:handler_instance) { described_class.new }

  describe '#initialize' do
    it 'loads the task configuration from YAML' do
      expect(handler_instance.config).to be_a(Hash)
      expect(handler_instance.config['name']).to eq('api_task/integration_yaml_example')
    end

    it 'validates the configuration' do
      expect(handler_instance.config).to include('step_templates')
      expect(handler_instance.config).to include('schema')
    end

    it 'builds the handler class automatically' do
      expect(handler_class.included_modules).to include(Tasker::TaskHandler)
      expect(handler_class::NAMED_STEPS).to eq(yaml_config['named_steps'])
      expect(handler_class::DEFAULT_DEPENDENT_SYSTEM).to eq('ecommerce_system')
    end
  end

  describe '.from_yaml' do
    it 'loads the configuration from the specified YAML file' do
      config = Tasker::TaskBuilder.from_yaml(yaml_path).config
      expect(config).to include('name' => 'api_task/integration_yaml_example')
      expect(config).to include('module_namespace' => 'ApiTask')
      expect(config).to include('task_handler_class' => 'IntegrationYamlExample')
    end
  end

  describe '#build' do
    let(:instance) { described_class.new }

    it 'builds and registers the handler class' do
      handler_class = instance.build
      expect(handler_class).to eq(described_class)
      expect(handler_class.included_modules).to include(Tasker::TaskHandler)
    end

    it 'defines named step constants' do
      expect(described_class::NAMED_STEPS).to eq(yaml_config['named_steps'])
    end

    it 'defines default dependent system constant' do
      expect(described_class::DEFAULT_DEPENDENT_SYSTEM).to eq('ecommerce_system')
    end

    it 'defines step templates with correct structure' do
      # Check that step templates are defined
      expect(handler_instance.config['step_templates'].count).to eq(5)

      # Check specific step template details
      cart_step = handler_instance.config['step_templates'].find { |s| s['name'] == 'fetch_cart' }
      expect(cart_step).to be_present
      expect(cart_step['handler_class']).to eq('ApiTask::StepHandler::CartFetchStepHandler')
      expect(cart_step['dependent_system']).to eq('ecommerce_system')

      # Check dependencies
      validate_step = handler_instance.config['step_templates'].find { |s| s['name'] == 'validate_products' }
      expect(validate_step['depends_on_steps']).to include('fetch_products', 'fetch_cart')

      order_step = handler_instance.config['step_templates'].find { |s| s['name'] == 'create_order' }
      expect(order_step['depends_on_step']).to eq('validate_products')
    end

    it 'defines schema method' do
      task = described_class.new
      expect(task).to respond_to(:schema)
      expect(task.schema).to include('type' => 'object')
      expect(task.schema['required']).to include('cart_id')
    end
  end
end
