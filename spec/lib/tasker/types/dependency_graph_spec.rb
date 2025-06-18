# typed: false
# frozen_string_literal: true

require 'rails_helper'

module Tasker
  module Types
    RSpec.describe 'Dependency Graph Types', type: :model do
      describe GraphNode do
        describe '.new' do
          context 'with minimal required attributes' do
            subject(:node) do
              described_class.new(
                id: 'step_1',
                name: 'validate_payment',
                type: 'step_template'
              )
            end

            it 'creates node with required attributes' do
              expect(node.id).to eq('step_1')
              expect(node.name).to eq('validate_payment')
              expect(node.type).to eq('step_template')
            end

            it 'sets default empty metadata' do
              expect(node.metadata).to eq({})
            end

            it 'has no state for template nodes' do
              expect(node.state).to be_nil
            end

            it 'has no readiness_status for template nodes' do
              expect(node.readiness_status).to be_nil
            end
          end

          context 'with runtime step attributes' do
            subject(:node) do
              described_class.new(
                id: '12345',
                name: 'validate_payment',
                type: 'workflow_step',
                state: 'in_progress',
                readiness_status: {
                  ready_for_execution: true,
                  dependencies_satisfied: true
                },
                metadata: {
                  step_class: 'ValidatePaymentStep',
                  retry_count: 2
                }
              )
            end

            it 'creates runtime node with all attributes' do
              expect(node.id).to eq('12345')
              expect(node.name).to eq('validate_payment')
              expect(node.type).to eq('workflow_step')
              expect(node.state).to eq('in_progress')
            end

            it 'includes readiness status' do
              expect(node.readiness_status).to eq({
                                                    ready_for_execution: true,
                                                    dependencies_satisfied: true
                                                  })
            end

            it 'includes metadata' do
              expect(node.metadata).to eq({
                                            step_class: 'ValidatePaymentStep',
                                            retry_count: 2
                                          })
            end
          end

          context 'with string keys' do
            subject(:node) do
              described_class.new(
                'id' => 'step_1',
                'name' => 'validate_payment',
                'type' => 'step_template'
              )
            end

            it 'transforms string keys to symbols' do
              expect(node.id).to eq('step_1')
              expect(node.name).to eq('validate_payment')
              expect(node.type).to eq('step_template')
            end
          end
        end

        describe 'type validation' do
          it 'requires id to be a string' do
            expect do
              described_class.new(
                id: 123,
                name: 'test',
                type: 'step_template'
              )
            end.to raise_error(Dry::Struct::Error)
          end

          it 'requires name to be a string' do
            expect do
              described_class.new(
                id: 'test',
                name: 123,
                type: 'step_template'
              )
            end.to raise_error(Dry::Struct::Error)
          end

          it 'requires type to be a string' do
            expect do
              described_class.new(
                id: 'test',
                name: 'test',
                type: 123
              )
            end.to raise_error(Dry::Struct::Error)
          end
        end
      end

      describe GraphEdge do
        describe '.new' do
          context 'with minimal required attributes' do
            subject(:edge) do
              described_class.new(
                from: 'step_1',
                to: 'step_2'
              )
            end

            it 'creates edge with required attributes' do
              expect(edge.from).to eq('step_1')
              expect(edge.to).to eq('step_2')
            end

            it 'sets default relationship type' do
              expect(edge.relationship).to eq('prerequisite')
            end

            it 'sets default empty metadata' do
              expect(edge.metadata).to eq({})
            end
          end

          context 'with custom attributes' do
            subject(:edge) do
              described_class.new(
                from: 'step_1',
                to: 'step_2',
                relationship: 'parallel',
                metadata: {
                  weight: 1.5,
                  critical_path: true
                }
              )
            end

            it 'uses custom relationship type' do
              expect(edge.relationship).to eq('parallel')
            end

            it 'includes metadata' do
              expect(edge.metadata).to eq({
                                            weight: 1.5,
                                            critical_path: true
                                          })
            end
          end
        end

        describe 'type validation' do
          it 'requires from to be a string' do
            expect do
              described_class.new(
                from: 123,
                to: 'step_2'
              )
            end.to raise_error(Dry::Struct::Error)
          end

          it 'requires to to be a string' do
            expect do
              described_class.new(
                from: 'step_1',
                to: 123
              )
            end.to raise_error(Dry::Struct::Error)
          end
        end
      end

      describe GraphMetadata do
        describe '.new' do
          context 'with template graph metadata' do
            subject(:metadata) do
              described_class.new(
                graph_type: 'template',
                handler_name: 'order_processing',
                total_nodes: 5,
                total_edges: 4
              )
            end

            it 'creates template metadata' do
              expect(metadata.graph_type).to eq('template')
              expect(metadata.handler_name).to eq('order_processing')
              expect(metadata.total_nodes).to eq(5)
              expect(metadata.total_edges).to eq(4)
            end

            it 'has no task_id for template graphs' do
              expect(metadata.task_id).to be_nil
            end

            it 'has no execution_context for template graphs' do
              expect(metadata.execution_context).to be_nil
            end
          end

          context 'with runtime graph metadata' do
            subject(:metadata) do
              described_class.new(
                graph_type: 'runtime',
                task_id: '12345',
                total_nodes: 5,
                total_edges: 4,
                execution_context: {
                  ready_steps: 2,
                  blocked_steps: 1,
                  completed_steps: 2
                },
                additional_data: {
                  critical_path_length: 3
                }
              )
            end

            it 'creates runtime metadata' do
              expect(metadata.graph_type).to eq('runtime')
              expect(metadata.task_id).to eq('12345')
              expect(metadata.total_nodes).to eq(5)
              expect(metadata.total_edges).to eq(4)
            end

            it 'includes execution context' do
              expect(metadata.execution_context).to eq({
                                                         ready_steps: 2,
                                                         blocked_steps: 1,
                                                         completed_steps: 2
                                                       })
            end

            it 'includes additional data' do
              expect(metadata.additional_data).to eq({
                                                       critical_path_length: 3
                                                     })
            end

            it 'has no handler_name for runtime graphs' do
              expect(metadata.handler_name).to be_nil
            end
          end
        end

        describe 'type validation' do
          it 'requires total_nodes to be an integer' do
            expect do
              described_class.new(
                graph_type: 'template',
                total_nodes: 'invalid',
                total_edges: 4
              )
            end.to raise_error(Dry::Struct::Error)
          end

          it 'requires total_edges to be an integer' do
            expect do
              described_class.new(
                graph_type: 'template',
                total_nodes: 5,
                total_edges: 'invalid'
              )
            end.to raise_error(Dry::Struct::Error)
          end
        end
      end

      describe DependencyGraph do
        let(:node1) do
          GraphNode.new(
            id: 'step_1',
            name: 'validate_payment',
            type: 'step_template'
          )
        end

        let(:node2) do
          GraphNode.new(
            id: 'step_2',
            name: 'update_inventory',
            type: 'step_template'
          )
        end

        let(:edge1) do
          GraphEdge.new(
            from: 'step_1',
            to: 'step_2'
          )
        end

        let(:metadata) do
          GraphMetadata.new(
            graph_type: 'template',
            handler_name: 'order_processing',
            total_nodes: 2,
            total_edges: 1
          )
        end

        describe '.new' do
          subject(:graph) do
            described_class.new(
              nodes: [node1, node2],
              edges: [edge1],
              metadata: metadata
            )
          end

          it 'creates dependency graph with all components' do
            expect(graph.nodes).to eq([node1, node2])
            expect(graph.edges).to eq([edge1])
            expect(graph.metadata).to eq(metadata)
          end

          it 'validates node count matches metadata' do
            expect(graph.nodes.length).to eq(graph.metadata.total_nodes)
          end

          it 'validates edge count matches metadata' do
            expect(graph.edges.length).to eq(graph.metadata.total_edges)
          end
        end

        describe 'type validation' do
          it 'requires nodes to be an array of GraphNode' do
            expect do
              described_class.new(
                nodes: ['invalid'],
                edges: [edge1],
                metadata: metadata
              )
            end.to raise_error(Dry::Struct::Error)
          end

          it 'requires edges to be an array of GraphEdge' do
            expect do
              described_class.new(
                nodes: [node1, node2],
                edges: ['invalid'],
                metadata: metadata
              )
            end.to raise_error(Dry::Struct::Error)
          end

          it 'requires metadata to be GraphMetadata' do
            expect do
              described_class.new(
                nodes: [node1, node2],
                edges: [edge1],
                metadata: 'invalid'
              )
            end.to raise_error(Dry::Struct::Error)
          end
        end

        describe 'immutability' do
          subject(:graph) do
            described_class.new(
              nodes: [node1, node2],
              edges: [edge1],
              metadata: metadata
            )
          end

          it 'creates frozen objects' do
            expect(graph).to be_frozen
          end

          it 'creates frozen arrays' do
            expect(graph.nodes).to be_frozen
            expect(graph.edges).to be_frozen
          end
        end

        describe 'equality' do
          let(:graph1) do
            described_class.new(
              nodes: [node1, node2],
              edges: [edge1],
              metadata: metadata
            )
          end

          let(:graph2) do
            described_class.new(
              nodes: [node1, node2],
              edges: [edge1],
              metadata: metadata
            )
          end

          let(:different_metadata) do
            GraphMetadata.new(
              graph_type: 'runtime',
              task_id: '12345',
              total_nodes: 2,
              total_edges: 1
            )
          end

          let(:graph3) do
            described_class.new(
              nodes: [node1, node2],
              edges: [edge1],
              metadata: different_metadata
            )
          end

          it 'equals other graphs with same values' do
            expect(graph1).to eq(graph2)
          end

          it 'does not equal graphs with different values' do
            expect(graph1).not_to eq(graph3)
          end
        end
      end
    end
  end
end
