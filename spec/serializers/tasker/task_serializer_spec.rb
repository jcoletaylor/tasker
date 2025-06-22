# typed: false
# frozen_string_literal: true

require 'rails_helper'
require_relative '../../mocks/dummy_task'

module Tasker
  RSpec.describe TaskSerializer, type: :serializer do
    let(:task_namespace) { create(:task_namespace, name: 'payments') }
    let(:named_task) { create(:named_task, name: 'process_payment', task_namespace: task_namespace, version: '1.2.0') }
    let(:task) { create(:task, named_task: named_task, reason: 'test serialization') }

    # Use find_or_create_by to avoid duplicates in other tests
    let(:default_task_namespace) { Tasker::TaskNamespace.find_or_create_by!(name: 'default') }
    let(:default_named_task) { create(:named_task, name: 'default_task', task_namespace: default_task_namespace) }
    let(:default_task) { create(:task, named_task: default_named_task) }

    before do
      register_task_handler(DummyTask::TASK_REGISTRY_NAME, DummyTask)
    end

    describe '#serializable_hash' do
      context 'with namespace and version information' do
        let(:serializer) { described_class.new(task) }
        let(:serialized_data) { serializer.serializable_hash }

        it 'includes basic task attributes' do
          expect(serialized_data[:task_id]).to eq(task.task_id)
          expect(serialized_data[:name]).to eq('process_payment')
          expect(serialized_data[:reason]).to eq('test serialization')
        end

        it 'includes namespace and version from named_task' do
          expect(serialized_data[:namespace]).to eq('payments')
          expect(serialized_data[:version]).to eq('1.2.0')
        end

        it 'includes computed full_name' do
          expect(serialized_data[:full_name]).to eq('payments.process_payment@1.2.0')
        end

        it 'includes all expected attributes' do
          expected_attributes = %i[
            task_id name namespace version full_name
            initiator source_system context reason
            bypass_steps tags requested_at complete status
          ]

          expected_attributes.each do |attr|
            expect(serialized_data).to have_key(attr)
          end
        end
      end

      context 'with default namespace and version' do
        let(:serializer) { described_class.new(default_task) }
        let(:serialized_data) { serializer.serializable_hash }

        it 'uses default values for namespace and version' do
          expect(serialized_data[:namespace]).to eq('default')
          expect(serialized_data[:version]).to eq('0.1.0')
          expect(serialized_data[:full_name]).to eq('default.default_task@0.1.0')
        end
      end

      context 'with missing named_task associations' do
        # Create a valid task but without task_namespace association on the named_task
        let(:orphaned_namespace) { create(:task_namespace, name: 'orphaned') }
        let(:orphaned_named_task) { create(:named_task, name: 'orphaned_task', task_namespace: orphaned_namespace) }
        let(:task_without_namespace_association) do
          # Create a task normally, then manually break the association for testing
          task = create(:task, named_task: orphaned_named_task)
          # Simulate a missing task_namespace association by stubbing the method
          allow(task.named_task).to receive(:task_namespace).and_return(nil)
          task
        end

        let(:serializer) { described_class.new(task_without_namespace_association) }
        let(:serialized_data) { serializer.serializable_hash }

        it 'falls back to default values when associations are missing' do
          expect(serialized_data[:namespace]).to eq('default')
          expect(serialized_data[:version]).to eq('0.1.0')
          expect(serialized_data[:full_name]).to match(/default\..*@0\.1\.0/)
        end
      end

      context 'with nil named_task' do
        # Use a new task instance with nil named_task to test serializer robustness
        let(:task_without_named_task) do
          # Create a task instance that bypasses validation for testing
          task = Tasker::Task.new(
            initiator: 'test',
            source_system: 'test',
            reason: 'serializer test',
            context: { test: true },
            complete: false,
            tags: [],
            bypass_steps: [],
            requested_at: Time.current
          )
          # Manually set the named_task to nil and ensure it has a name method
          task.named_task = nil
          # Stub the name method to return a test value since delegation will fail
          allow(task).to receive(:name).and_return('test_task_without_named_task')
          task
        end

        let(:serializer) { described_class.new(task_without_named_task) }
        let(:serialized_data) { serializer.serializable_hash }

        it 'handles missing named_task gracefully' do
          expect(serialized_data[:namespace]).to eq('default')
          expect(serialized_data[:version]).to eq('0.1.0')
          # full_name will still work because it uses the namespace and version methods
          expect(serialized_data[:full_name]).to include('default')
          expect(serialized_data[:full_name]).to include('@0.1.0')
        end
      end

      context 'with various version formats' do
        let(:versioned_named_task) { create(:named_task, name: 'versioned_task', version: '2.1.3') }
        let(:versioned_task) { create(:task, named_task: versioned_named_task) }
        let(:serializer) { described_class.new(versioned_task) }
        let(:serialized_data) { serializer.serializable_hash }

        it 'handles semantic version correctly' do
          expect(serialized_data[:version]).to eq('2.1.3')
          expect(serialized_data[:full_name]).to eq('default.versioned_task@2.1.3')
        end
      end

      context 'with different namespace names' do
        %w[api_integrations inventory_management notifications].each do |namespace_name|
          context "with #{namespace_name} namespace" do
            let(:specific_namespace) { create(:task_namespace, name: namespace_name) }
            let(:specific_named_task) { create(:named_task, name: 'test_task', task_namespace: specific_namespace) }
            let(:specific_task) { create(:task, named_task: specific_named_task) }
            let(:serializer) { described_class.new(specific_task) }
            let(:serialized_data) { serializer.serializable_hash }

            it "correctly serializes #{namespace_name} namespace" do
              expect(serialized_data[:namespace]).to eq(namespace_name)
              expect(serialized_data[:full_name]).to eq("#{namespace_name}.test_task@0.1.0")
            end
          end
        end
      end

      context 'with associations loaded' do
        it 'includes associated data alongside namespace information' do
          t = create(:task, named_task: named_task, reason: 'association test')

          # Just verify that the serializer works with a task that has associations available
          # The task already has workflow_steps and task_annotations associations defined

          serializer = described_class.new(t)
          result = serializer.serializable_hash

          # Check that namespace info is included
          expect(result[:namespace]).to eq('payments')
          expect(result[:version]).to eq('1.2.0')
          expect(result[:full_name]).to eq('payments.process_payment@1.2.0')

          # Verify the serializer includes association keys (even if empty)
          expect(result).to have_key(:workflow_steps)
          expect(result).to have_key(:task_annotations)
        end
      end
    end

    describe 'attribute delegation' do
      let(:serializer) { described_class.new(task) }

      it 'properly delegates to named_task associations' do
        # Test that the methods work correctly
        expect(serializer.namespace).to eq('payments')
        expect(serializer.version).to eq('1.2.0')
        expect(serializer.full_name).to eq('payments.process_payment@1.2.0')
      end
    end

    describe 'backward compatibility' do
      let(:serializer) { described_class.new(task) }
      let(:serialized_data) { serializer.serializable_hash }

      it 'maintains all existing task attributes' do
        # Verify all original TaskSerializer attributes are still present
        original_attributes = %i[
          task_id name initiator source_system context reason
          bypass_steps tags requested_at complete status
        ]

        original_attributes.each do |attr|
          expect(serialized_data).to have_key(attr), "Missing original attribute: #{attr}"
        end
      end

      it 'includes workflow_steps and task_annotations associations' do
        expect(serialized_data).to have_key(:workflow_steps)
        expect(serialized_data).to have_key(:task_annotations)
      end
    end

    describe 'dependency analysis serialization' do
      # Use a dummy task with actual workflow steps for dependency analysis testing
      let(:dummy_task) { create_dummy_task_workflow(context: { dummy: true }, reason: 'serializer test') }

      describe 'basic serialization without dependency analysis' do
        let(:serializer) { described_class.new(dummy_task) }
        let(:serialized_data) { serializer.serializable_hash }

        it 'includes all expected attributes' do
          expect(serialized_data[:task_id]).to eq(dummy_task.task_id)
          expect(serialized_data[:name]).to eq(dummy_task.name)
          expect(serialized_data[:namespace]).to eq('default')
          expect(serialized_data[:version]).to eq('0.1.0')
          expect(serialized_data[:full_name]).to eq('default.dummy_task@0.1.0')
          expect(serialized_data[:workflow_steps]).to be_present
          expect(serialized_data).to have_key(:task_annotations)
        end

        it 'does not include dependency analysis by default' do
          expect(serialized_data).not_to have_key(:dependency_analysis)
        end
      end

      describe 'with dependency analysis enabled' do
        let(:serializer) { described_class.new(dummy_task, include_dependencies: true) }
        let(:serialized_data) { serializer.serializable_hash }

        it 'includes dependency analysis when requested' do
          expect(serialized_data[:dependency_analysis]).to be_present
        end

        it 'includes all dependency analysis components' do
          dependency_analysis = serialized_data[:dependency_analysis]

          expect(dependency_analysis[:dependency_graph]).to be_present
          expect(dependency_analysis[:critical_paths]).to be_present
          expect(dependency_analysis[:parallelism_opportunities]).to be_present
          expect(dependency_analysis[:error_chains]).to be_present
          expect(dependency_analysis[:bottlenecks]).to be_present
          expect(dependency_analysis[:analysis_timestamp]).to be_present
          expect(dependency_analysis[:task_execution_summary]).to be_present
        end

        it 'includes task execution summary with correct structure' do
          summary = serialized_data[:dependency_analysis][:task_execution_summary]

          expect(summary[:total_steps]).to be_a(Integer)
          expect(summary[:total_dependencies]).to be_a(Integer)
          expect(summary[:dependency_levels]).to be_a(Integer)
          expect(summary[:longest_path_length]).to be_a(Integer)
          expect(summary[:critical_bottlenecks_count]).to be_a(Integer)
          expect(summary[:error_chains_count]).to be_a(Integer)
          expect(summary[:parallelism_efficiency]).to be_a(Numeric)
          expect(summary[:overall_health]).to be_in(%w[healthy warning critical])
          expect(summary[:recommendations]).to be_an(Array)
        end

        it 'includes dependency graph structure' do
          graph = serialized_data[:dependency_analysis][:dependency_graph]

          expect(graph[:nodes]).to be_an(Array)
          expect(graph[:edges]).to be_an(Array)
          expect(graph[:adjacency_list]).to be_a(Hash)
          expect(graph[:reverse_adjacency_list]).to be_a(Hash)
          expect(graph[:dependency_levels]).to be_a(Hash)
        end
      end

      describe 'error handling in dependency analysis' do
        let(:serializer) { described_class.new(dummy_task, include_dependencies: true) }

        before do
          # Mock the dependency_graph method to raise an error
          allow(dummy_task).to receive(:dependency_graph).and_raise(StandardError, 'Test analysis error')
        end

        it 'gracefully handles dependency analysis errors' do
          serialized_data = serializer.serializable_hash
          dependency_analysis = serialized_data[:dependency_analysis]

          expect(dependency_analysis[:error]).to include('Test analysis error')
          expect(dependency_analysis[:analysis_timestamp]).to be_present
        end
      end

      describe 'conditional inclusion logic' do
        it 'includes dependency analysis when include_dependencies is true' do
          serializer = described_class.new(dummy_task, include_dependencies: true)
          expect(serializer.include_dependency_analysis?).to be true
        end

        it 'excludes dependency analysis when include_dependencies is false' do
          serializer = described_class.new(dummy_task, include_dependencies: false)
          expect(serializer.include_dependency_analysis?).to be false
        end

        it 'excludes dependency analysis when include_dependencies is not specified' do
          serializer = described_class.new(dummy_task)
          expect(serializer.include_dependency_analysis?).to be false
        end
      end
    end
  end
end
