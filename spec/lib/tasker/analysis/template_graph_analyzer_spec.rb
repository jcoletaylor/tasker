# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Analysis::TemplateGraphAnalyzer do
  subject(:analyzer) { described_class.new(templates) }

  let(:handler) { LinearWorkflowTask.new }
  let(:templates) { handler.step_templates }

  describe '#initialize' do
    it 'stores the templates' do
      expect(analyzer.templates).to eq(templates)
    end
  end

  describe '#analyze' do
    subject(:analysis) { analyzer.analyze }

    it 'returns comprehensive dependency analysis' do
      expect(analysis).to include(
        :nodes, :edges, :topology, :cycles, :levels, :roots, :leaves, :summary
      )
    end

    it 'caches the analysis result' do
      first_result = analyzer.analyze
      second_result = analyzer.analyze
      expect(first_result).to be(second_result) # Same object reference
    end

    it 'provides correct node information' do
      nodes = analysis[:nodes]
      expect(nodes).to be_an(Array)
      expect(nodes.size).to eq(6) # Linear workflow has 6 steps

      first_node = nodes.first
      expect(first_node).to include(:name, :description, :handler_class, :dependencies, :dependency_count)
    end

    it 'provides correct edge information' do
      edges = analysis[:edges]
      expect(edges).to be_an(Array)
      expect(edges.size).to eq(5) # 5 dependencies in linear workflow

      first_edge = edges.first
      expect(first_edge).to include(:from, :to, :type)
    end
  end

  describe '#has_cycles?' do
    context 'with linear workflow' do
      it 'returns false' do
        expect(analyzer.has_cycles?).to be false
      end
    end
  end

  describe '#topology' do
    it 'returns correct topological order for linear workflow' do
      expected_order = %w[initialize_data validate_input process_data transform_results validate_output
                          finalize_workflow]
      expect(analyzer.topology).to eq(expected_order)
    end
  end

  describe '#roots' do
    it 'identifies root steps correctly' do
      expect(analyzer.roots).to contain_exactly('initialize_data')
    end
  end

  describe '#leaves' do
    it 'identifies leaf steps correctly' do
      expect(analyzer.leaves).to contain_exactly('finalize_workflow')
    end
  end

  describe '#levels' do
    it 'calculates dependency levels correctly' do
      levels = analyzer.levels
      expect(levels['initialize_data']).to eq(0)
      expect(levels['validate_input']).to eq(1)
      expect(levels['finalize_workflow']).to eq(5)
    end
  end

  describe '#clear_cache!' do
    it 'clears the analysis cache' do
      first_result = analyzer.analyze
      analyzer.clear_cache!
      second_result = analyzer.analyze
      expect(first_result).not_to be(second_result) # Different object references
    end
  end

  context 'with diamond workflow (convergent dependencies)' do
    let(:handler) { DiamondWorkflowTask.new }

    it 'handles multiple dependencies correctly' do
      analysis = analyzer.analyze

      # Find the merge step that depends on both branches
      merge_node = analysis[:nodes].find { |n| n[:name] == 'merge_branches' }
      expect(merge_node[:dependencies]).to contain_exactly('branch_one_validate', 'branch_two_validate')

      # Should have higher parallelism than linear workflow
      expect(analysis[:summary][:parallel_branches]).to be > 1
    end

    it 'detects no cycles in diamond pattern' do
      expect(analyzer.has_cycles?).to be false
    end
  end

  context 'with circular dependencies' do
    let(:circular_templates) do
      [
        double('Template A',
               name: 'step_a',
               description: 'Step A description',
               handler_class: double('HandlerA', name: 'HandlerA'),
               all_dependencies: ['step_b'],
               depends_on_step: 'step_b'),
        double('Template B',
               name: 'step_b',
               description: 'Step B description',
               handler_class: double('HandlerB', name: 'HandlerB'),
               all_dependencies: ['step_a'],
               depends_on_step: 'step_a')
      ]
    end
    let(:analyzer) { described_class.new(circular_templates) }

    it 'detects circular dependencies' do
      expect(analyzer.has_cycles?).to be true
      expect(analyzer.cycles).not_to be_empty
    end

    it 'returns empty topology when cycles exist' do
      expect(analyzer.topology).to be_empty
    end
  end
end
