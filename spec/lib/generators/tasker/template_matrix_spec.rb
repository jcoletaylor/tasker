# frozen_string_literal: true

require 'rails_helper'
require 'erb'
require 'yaml'

RSpec.describe 'Template Matrix Validation' do
  include TemplateTestHelpers

  # Test combinations that exercise different ERB conditionals and paths
  TEMPLATE_COMBINATIONS = [
    {
      name: 'minimal_task',
      bindings: {
        task_name: 'simple_task',
        task_handler_class: 'SimpleTaskHandler',
        namespace_name: 'default',
        version: '1.0.0'
      }
    },
    {
      name: 'with_module_namespace',
      bindings: {
        task_name: 'namespaced_task',
        task_handler_class: 'NamespacedTaskHandler',
        module_namespace: 'MyModule',
        namespace_name: 'ecommerce',
        version: '2.1.0'
      }
    },
    {
      name: 'with_custom_steps',
      bindings: {
        task_name: 'custom_steps_task',
        task_handler_class: 'CustomStepsTaskHandler',
        steps: %w[validate_input process_data send_notification],
        namespace_name: 'workflows',
        version: '1.5.0'
      }
    },
    {
      name: 'with_dependent_system',
      bindings: {
        task_name: 'dependent_task',
        task_handler_class: 'DependentTaskHandler',
        dependent_system: 'payment_gateway',
        namespace_name: 'payments',
        version: '3.0.0'
      }
    },
    {
      name: 'with_description',
      bindings: {
        task_name: 'described_task',
        task_handler_class: 'DescribedTaskHandler',
        description: 'A task with a custom description',
        namespace_name: 'custom',
        version: '0.5.0'
      }
    },
    {
      name: 'full_featured',
      bindings: {
        task_name: 'full_featured_task',
        task_handler_class: 'FullFeaturedTaskHandler',
        module_namespace: 'Enterprise',
        steps: %w[authenticate validate process notify],
        dependent_system: 'enterprise_api',
        description: 'A fully featured task with all options',
        namespace_name: 'enterprise',
        version: '4.2.1'
      }
    }
  ].freeze

  TEMPLATES = %w[
    task_handler.rb.erb
    task_config.yaml.erb
    task_handler_spec.rb.erb
  ].freeze

  describe 'Template Rendering' do
    TEMPLATE_COMBINATIONS.each do |combination|
      context "with #{combination[:name]}" do
        let(:bindings) { combination[:bindings] }

        TEMPLATES.each do |template_name|
          it "renders #{template_name} without errors" do
            expect { render_template(template_name, bindings) }.not_to raise_error
          end

          it "generates non-empty output for #{template_name}" do
            rendered = render_template(template_name, bindings)
            expect(rendered.strip).not_to be_empty
          end
        end
      end
    end
  end

  describe 'Generated Code Syntax Validation' do
    TEMPLATE_COMBINATIONS.each do |combination|
      context "with #{combination[:name]}" do
        let(:bindings) { combination[:bindings] }

        it 'generates syntactically valid Ruby for task_handler.rb.erb' do
          rendered = render_template('task_handler.rb.erb', bindings)
          expect(validate_ruby_syntax(rendered)).to be true
        end

        it 'generates syntactically valid Ruby for task_handler_spec.rb.erb' do
          rendered = render_template('task_handler_spec.rb.erb', bindings)
          expect(validate_ruby_syntax(rendered)).to be true
        end

        it 'generates valid YAML for task_config.yaml.erb' do
          rendered = render_template('task_config.yaml.erb', bindings)
          expect(validate_yaml_syntax(rendered)).to be true
        end
      end
    end
  end

  describe 'Generated Code Content Validation' do
    TEMPLATE_COMBINATIONS.each do |combination|
      context "with #{combination[:name]}" do
        let(:bindings) { combination[:bindings] }

        describe 'task_handler.rb.erb' do
          let(:rendered_handler) { render_template('task_handler.rb.erb', bindings) }

          it 'includes the correct class name' do
            expect(rendered_handler).to include("class #{bindings[:task_handler_class]}")
          end

          it 'includes FetchDataStepHandler class' do
            expect(rendered_handler).to include('class FetchDataStepHandler')
          end

          it 'includes ProcessDataStepHandler class' do
            expect(rendered_handler).to include('class ProcessDataStepHandler')
          end

          it 'includes CompleteTaskStepHandler class' do
            expect(rendered_handler).to include('class CompleteTaskStepHandler')
          end

          it 'includes correct module namespace when specified' do
            if bindings[:module_namespace]
              expect(rendered_handler).to include("module #{bindings[:module_namespace]}")
            else
              expect(rendered_handler).not_to include('module ')
            end
          end

          it 'includes correct process_results method signature' do
            expect(rendered_handler).to include('def process_results(step, response, initial_results)')
          end
        end

        describe 'task_config.yaml.erb' do
          let(:rendered_config) { render_template('task_config.yaml.erb', bindings) }
          let(:parsed_config) { YAML.safe_load(rendered_config) }

          it 'includes correct task name' do
            expect(parsed_config['name']).to eq(bindings[:task_name])
          end

          it 'includes correct task handler class' do
            expect(parsed_config['task_handler_class']).to eq(bindings[:task_handler_class])
          end

          it 'includes correct namespace' do
            expect(parsed_config['namespace_name']).to eq(bindings[:namespace_name])
          end

          it 'includes correct version' do
            expect(parsed_config['version']).to eq(bindings[:version])
          end

          it 'includes default_dependent_system' do
            expected_system = bindings[:dependent_system] || 'default_system'
            expect(parsed_config['default_dependent_system']).to eq(expected_system)
          end

          it 'includes named_steps' do
            expect(parsed_config['named_steps']).to be_an(Array)
            expect(parsed_config['named_steps']).not_to be_empty
          end

          it 'includes step_templates' do
            expect(parsed_config['step_templates']).to be_an(Array)
            expect(parsed_config['step_templates']).not_to be_empty
          end

          it 'includes schema definition' do
            expect(parsed_config['schema']).to be_a(Hash)
            expect(parsed_config['schema']['type']).to eq('object')
          end

          it 'includes environment configurations' do
            expect(parsed_config['environments']).to be_a(Hash)
            expect(parsed_config['environments']).to have_key('development')
            expect(parsed_config['environments']).to have_key('test')
            expect(parsed_config['environments']).to have_key('production')
          end

          it 'uses custom steps when provided' do
            if bindings[:steps]
              expect(parsed_config['named_steps']).to eq(bindings[:steps])
            else
              expect(parsed_config['named_steps']).to eq(%w[fetch_data process_data complete_task])
            end
          end
        end

        describe 'task_handler_spec.rb.erb' do
          let(:rendered_spec) { render_template('task_handler_spec.rb.erb', bindings) }

          it 'includes the correct RSpec describe block' do
            if bindings[:module_namespace]
              expect(rendered_spec).to include("RSpec.describe #{bindings[:module_namespace]}::#{bindings[:task_handler_class]}")
            else
              expect(rendered_spec).to include("RSpec.describe #{bindings[:task_handler_class]}")
            end
          end

          it 'includes task request with correct parameters' do
            expect(rendered_spec).to include("name: \"#{bindings[:task_name]}\"")
            expect(rendered_spec).to include("namespace: \"#{bindings[:namespace_name]}\"")
            expect(rendered_spec).to include("version: \"#{bindings[:version]}\"")
          end

          it 'includes factory registration with replace: true' do
            expect(rendered_spec).to include('replace: true')
          end

          it 'includes helper method definition' do
            expect(rendered_spec).to include('def create_api_task_handler_with_connection')
          end

          it 'includes proper API endpoint stubs' do
            expect(rendered_spec).to include("stubs.get(\"/data/\#{input_id}\")")
            expect(rendered_spec).to include('stubs.get("/data")')
          end

          it 'includes workflow validation tests' do
            expect(rendered_spec).to include("describe 'complete workflow'")
            expect(rendered_spec).to include("it 'can handle the task'")
          end
        end
      end
    end
  end

  describe 'Template Consistency' do
    TEMPLATE_COMBINATIONS.each do |combination|
      context "with #{combination[:name]}" do
        let(:bindings) { combination[:bindings] }
        let(:rendered_handler) { render_template('task_handler.rb.erb', bindings) }
        let(:rendered_config) { render_template('task_config.yaml.erb', bindings) }
        let(:rendered_spec) { render_template('task_handler_spec.rb.erb', bindings) }
        let(:parsed_config) { YAML.safe_load(rendered_config) }

        it 'maintains consistent class names across templates' do
          handler_class = bindings[:task_handler_class]

          # Check handler file
          expect(rendered_handler).to include("class #{handler_class}")

          # Check config file
          expect(parsed_config['task_handler_class']).to eq(handler_class)

          # Check spec file
          if bindings[:module_namespace]
            expect(rendered_spec).to include("#{bindings[:module_namespace]}::#{handler_class}")
          else
            expect(rendered_spec).to include(handler_class)
          end
        end

        it 'maintains consistent task names across templates' do
          task_name = bindings[:task_name]

          # Check config file
          expect(parsed_config['name']).to eq(task_name)

          # Check spec file
          expect(rendered_spec).to include("name: \"#{task_name}\"")
        end

        it 'maintains consistent namespace and version across templates' do
          namespace = bindings[:namespace_name]
          version = bindings[:version]

          # Check config file
          expect(parsed_config['namespace_name']).to eq(namespace)
          expect(parsed_config['version']).to eq(version)

          # Check spec file
          expect(rendered_spec).to include("namespace: \"#{namespace}\"")
          expect(rendered_spec).to include("version: \"#{version}\"")
        end
      end
    end
  end
end
