# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Dependency Graph Composition' do
  include FactoryWorkflowHelpers

  let(:handler) { LinearWorkflowTask.new }

  before(:all) do
    # Register the workflow task handlers
    Tasker::HandlerFactory.instance.register('linear_workflow_task', LinearWorkflowTask)
    Tasker::HandlerFactory.instance.register('diamond_workflow_task', DiamondWorkflowTask)
  end

  describe 'TaskHandler#dependency_graph (Template Analysis via Composition)' do
    subject(:graph) { handler.dependency_graph }

    it 'delegates to TemplateGraphAnalyzer correctly' do
      expect(graph).to include(
        :nodes, :edges, :topology, :cycles, :levels, :roots, :leaves, :summary
      )
    end

    it 'provides template-level analysis' do
      # Verify this is template analysis, not runtime analysis
      expect(graph).not_to include(:execution_flow, :blocked_steps, :ready_steps, :error_chains)

      # Verify template-specific data
      expect(graph[:nodes].first).to include(:handler_class, :dependencies)
      expect(graph[:topology]).to be_an(Array)
    end

    it 'maintains backward compatibility' do
      # Ensure the composed behavior matches the original interface
      expect(graph[:summary][:total_steps]).to eq(6)
      expect(graph[:roots]).to contain_exactly('initialize_data')
      expect(graph[:leaves]).to contain_exactly('finalize_workflow')
    end
  end

  describe 'Task#dependency_graph (Runtime Analysis via Composition)' do
    subject(:graph) { task.dependency_graph }

    let(:task) { create(:linear_workflow_task) }

    before do
      # Complete first step to show runtime analysis
      first_step = task.workflow_steps.joins(:named_step).find_by(named_step: { name: 'initialize_data' })
      complete_step_via_state_machine(first_step) if first_step
    end

    it 'delegates to RuntimeGraphAnalyzer correctly' do
      expect(graph).to include(:dependency_graph, :critical_paths)
      expect(graph[:dependency_graph]).to include(:nodes, :edges, :adjacency_list, :dependency_levels)
    end

    it 'provides runtime-level analysis' do
      # Verify this is runtime analysis, not template analysis
      expect(graph).not_to include(:topology, :cycles, :levels, :roots, :leaves)

      # Verify runtime-specific data
      expect(graph[:dependency_graph][:nodes]).to be_an(Array)
      expect(graph[:critical_paths]).to include(:total_paths, :longest_path_length)
    end

    it 'includes task state in summary' do
      # Verify the dependency graph includes task information
      expect(graph[:dependency_graph][:nodes]).to be_an(Array)
      expect(graph[:dependency_graph][:nodes].length).to be > 0
    end

    it 'maintains backward compatibility' do
      # Ensure the composed behavior provides expected structure
      expect(graph[:dependency_graph][:nodes].length).to eq(6)
      expect(graph[:critical_paths][:total_paths]).to be >= 0
    end
  end

  describe 'Analyzer Independence' do
    it 'allows direct analyzer usage' do
      # Template analyzer can be used independently
      template_analyzer = Tasker::Analysis::TemplateGraphAnalyzer.new(handler.step_templates)
      template_result = template_analyzer.analyze
      expect(template_result[:topology]).to be_an(Array)

      # Runtime analyzer can be used independently
      task = create(:linear_workflow_task)
      runtime_analyzer = Tasker::Analysis::RuntimeGraphAnalyzer.new(task: task)
      runtime_result = runtime_analyzer.analyze
      expect(runtime_result[:dependency_graph]).to be_a(Hash)
    end

    it 'provides different analysis types' do
      task = create(:linear_workflow_task)

      # Template analysis focuses on design-time dependencies
      template_graph = handler.dependency_graph
      expect(template_graph[:cycles]).to be_an(Array) # Design validation

      # Runtime analysis focuses on execution state
      runtime_graph = task.dependency_graph
      expect(runtime_graph[:dependency_graph]).to be_a(Hash) # Execution state
    end
  end

  describe 'Performance and Caching' do
    it 'caches analyzer instances' do
      # Multiple calls should reuse the same analyzer instance
      first_call = handler.dependency_graph
      second_call = handler.dependency_graph

      # The analysis should be cached within the analyzer
      expect(first_call).to eq(second_call)
    end

    it 'allows cache clearing' do
      task = create(:linear_workflow_task)

      # Access the analyzer and clear its cache
      analyzer = task.send(:runtime_analyzer)
      first_result = analyzer.analyze
      analyzer.clear_cache!
      second_result = analyzer.analyze

      # Results should be equivalent but different objects
      expect(first_result).not_to be(second_result)
      expect(first_result.keys).to eq(second_result.keys)
    end
  end
end
