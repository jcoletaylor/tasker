# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Analysis::RuntimeGraphAnalyzer do
  include FactoryWorkflowHelpers

  # Use the proper complex workflow factory
  subject(:analyzer) { described_class.new(task: task) }

  let(:task) { create(:linear_workflow_task) }

  before(:all) do
    # Register the workflow task handlers
    Tasker::HandlerFactory.instance.register('linear_workflow_task', LinearWorkflowTask)
    Tasker::HandlerFactory.instance.register('diamond_workflow_task', DiamondWorkflowTask)
  end

  describe '#initialize' do
    it 'stores the task and task_id' do
      expect(analyzer.task).to eq(task)
      expect(analyzer.task_id).to eq(task.task_id)
    end
  end

  describe '#analyze' do
    let(:analysis) { analyzer.analyze }

    it 'returns focused graph analysis structure' do
      expect(analysis).to include(:dependency_graph, :critical_paths)
    end

    describe 'dependency_graph' do
      let(:dependency_graph) { analysis[:dependency_graph] }

      it 'builds graph from workflow_step_edges' do
        expect(dependency_graph).to include(:nodes, :edges, :adjacency_list, :reverse_adjacency_list,
                                            :dependency_levels)
      end

      it 'includes node information with dependency levels' do
        nodes = dependency_graph[:nodes]
        expect(nodes).to be_an(Array)
        expect(nodes.first).to include(:id, :name, :level)
      end

      it 'includes edge information with names' do
        edges = dependency_graph[:edges]
        expect(edges).to be_an(Array)

        expect(edges.first).to include(:from, :to, :from_name, :to_name) if edges.any?
      end

      it 'calculates dependency levels using SQL topological sort' do
        dependency_levels = dependency_graph[:dependency_levels]
        expect(dependency_levels).to be_a(Hash)

        # All levels should be non-negative integers
        dependency_levels.each_value do |level|
          expect(level).to be >= 0
        end
      end
    end

    describe 'critical_paths' do
      let(:critical_paths) { analysis[:critical_paths] }

      it 'analyzes critical paths through the graph' do
        expect(critical_paths).to include(:total_paths, :longest_path_length, :paths, :root_nodes, :leaf_nodes)
      end

      it 'identifies root and leaf nodes' do
        expect(critical_paths[:root_nodes]).to be_an(Array)
        expect(critical_paths[:leaf_nodes]).to be_an(Array)
      end

      it 'provides path analysis with step readiness data' do
        paths = critical_paths[:paths]
        expect(paths).to be_an(Array)

        if paths.any?
          path = paths.first
          expect(path).to include(:path, :length, :step_names, :completed_steps, :blocked_steps, :error_steps)
        end
      end
    end
  end

  describe '#clear_cache!' do
    it 'clears the analysis cache' do
      # Access analysis to populate cache
      first_analysis = analyzer.analyze

      # Clear cache
      analyzer.clear_cache!

      # Get analysis again - should be recalculated
      second_analysis = analyzer.analyze

      # Should have same structure but be different objects
      expect(first_analysis.keys).to eq(second_analysis.keys)
      expect(first_analysis).not_to be(second_analysis)
    end
  end

  context 'with diamond workflow (parallel branches)' do
    let(:task) { create(:diamond_workflow_task) }

    it 'handles parallel dependency structures' do
      analysis = analyzer.analyze
      dependency_graph = analysis[:dependency_graph]

      # Should have multiple dependency levels for parallel structure
      levels = dependency_graph[:dependency_levels].values.uniq.sort
      expect(levels.length).to be > 1
    end

    it 'identifies multiple critical paths' do
      analysis = analyzer.analyze
      critical_paths = analysis[:critical_paths]

      # Diamond workflow should have multiple paths
      expect(critical_paths[:total_paths]).to be > 1
    end
  end

  context 'with completed steps' do
    before do
      # Complete first step to show runtime analysis
      first_step = task.workflow_steps.joins(:named_step).find_by(named_step: { name: 'initialize_data' })
      complete_step_via_state_machine(first_step) if first_step
    end

    it 'reflects step completion in path analysis' do
      analysis = analyzer.analyze
      paths = analysis[:critical_paths][:paths]

      if paths.any?
        # At least one path should show completed steps
        completed_counts = paths.map { |p| p[:completed_steps] }
        expect(completed_counts.sum).to be > 0
      end
    end
  end

  describe 'SQL-based topological sort performance' do
    it 'uses SQL for dependency level calculation' do
      # Verify that the SQL query executes without error
      expect { analyzer.analyze }.not_to raise_error

      # Verify dependency levels are calculated
      dependency_levels = analyzer.analyze[:dependency_graph][:dependency_levels]
      expect(dependency_levels).to be_a(Hash)
      expect(dependency_levels.keys).to all(be_an(Integer))
      expect(dependency_levels.values).to all(be_an(Integer))
    end
  end
end
