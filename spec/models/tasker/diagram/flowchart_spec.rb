# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Diagram::Flowchart do
  describe 'basic functionality' do
    let(:node_label_a) { Tasker::Diagram::Node.new(id: 'A', label: 'Node A') }
    let(:node_label_b) { Tasker::Diagram::Node.new(id: 'B', label: 'Node B') }
    let(:edge) { Tasker::Diagram::Edge.new(source_id: 'A', target_id: 'B', label: 'connects to') }
    let(:flowchart) { described_class.new(direction: 'LR', title: 'Test Chart') }

    before do
      flowchart.add_node(node_label_a)
      flowchart.add_node(node_label_b)
      flowchart.add_edge(edge)
    end

    it 'stores nodes and edges' do
      expect(flowchart.nodes).to contain_exactly(node_label_a, node_label_b)
      expect(flowchart.edges).to contain_exactly(edge)
    end

    it 'finds nodes by ID' do
      expect(flowchart.find_node('A')).to eq(node_label_a)
      expect(flowchart.find_node('B')).to eq(node_label_b)
      expect(flowchart.find_node('C')).to be_nil
    end

    it 'finds edges for nodes' do
      # Outgoing edges from A
      expect(flowchart.find_edges_for_node('A', :outgoing)).to contain_exactly(edge)

      # Incoming edges to B
      expect(flowchart.find_edges_for_node('B', :incoming)).to contain_exactly(edge)

      # All edges for A (both directions)
      expect(flowchart.find_edges_for_node('A')).to contain_exactly(edge)

      # All edges for B (both directions)
      expect(flowchart.find_edges_for_node('B')).to contain_exactly(edge)

      # Node with no edges
      expect(flowchart.find_edges_for_node('C')).to be_empty
    end

    it 'converts to hash' do
      hash = flowchart.to_h
      expect(hash[:nodes].length).to eq(2)
      expect(hash[:edges].length).to eq(1)
      expect(hash[:direction]).to eq('LR')
      expect(hash[:title]).to eq('Test Chart')
    end

    it 'converts to JSON' do
      json = flowchart.to_json
      expect(json).to be_a(String)
      parsed = JSON.parse(json)
      expect(parsed['nodes'].length).to eq(2)
      expect(parsed['edges'].length).to eq(1)
      expect(parsed['direction']).to eq('LR')
      expect(parsed['title']).to eq('Test Chart')
    end
  end

  describe '#to_mermaid' do
    it 'generates basic mermaid syntax' do
      flowchart = described_class.new(direction: 'TD')
      flowchart.add_node(Tasker::Diagram::Node.new(id: 'A', label: 'Start'))
      flowchart.add_node(Tasker::Diagram::Node.new(id: 'B', label: 'End'))
      flowchart.add_edge(Tasker::Diagram::Edge.new(source_id: 'A', target_id: 'B'))

      mermaid = flowchart.to_mermaid
      expect(mermaid).to include('graph TD')
      expect(mermaid).to include('A["Start"]')
      expect(mermaid).to include('B["End"]')
      expect(mermaid).to include('A -- --> B')
    end

    it 'includes title when provided' do
      flowchart = described_class.new(direction: 'TD', title: 'Process Flow')
      mermaid = flowchart.to_mermaid
      expect(mermaid).to include('title Process Flow')
    end

    it 'handles node styles' do
      flowchart = described_class.new(direction: 'TD')
      flowchart.add_node(Tasker::Diagram::Node.new(
                           id: 'A',
                           label: 'Styled Node',
                           style: 'fill:red;stroke:blue;'
                         ))

      mermaid = flowchart.to_mermaid
      expect(mermaid).to include('A["Styled Node"]')
    end

    it 'handles node URLs' do
      flowchart = described_class.new(direction: 'TD')
      flowchart.add_node(Tasker::Diagram::Node.new(
                           id: 'A',
                           label: 'Clickable Node',
                           url: 'https://example.com'
                         ))

      mermaid = flowchart.to_mermaid
      expect(mermaid).to include('click A "https://example.com"')
    end

    it 'handles different edge types' do
      flowchart = described_class.new(direction: 'TD')
      flowchart.add_node(Tasker::Diagram::Node.new(id: 'A', label: 'Start'))
      flowchart.add_node(Tasker::Diagram::Node.new(id: 'B', label: 'Middle'))
      flowchart.add_node(Tasker::Diagram::Node.new(id: 'C', label: 'End'))

      # Solid edge
      flowchart.add_edge(Tasker::Diagram::Edge.new(
                           source_id: 'A',
                           target_id: 'B',
                           type: 'solid'
                         ))

      # Dashed edge
      flowchart.add_edge(Tasker::Diagram::Edge.new(
                           source_id: 'B',
                           target_id: 'C',
                           type: 'dashed'
                         ))

      mermaid = flowchart.to_mermaid
      expect(mermaid).to include('A -- --> B')
      expect(mermaid).to include('B -- --> C')
    end

    it 'handles edge labels' do
      flowchart = described_class.new(direction: 'TD')
      flowchart.add_node(Tasker::Diagram::Node.new(id: 'A', label: 'Start'))
      flowchart.add_node(Tasker::Diagram::Node.new(id: 'B', label: 'End'))

      flowchart.add_edge(Tasker::Diagram::Edge.new(
                           source_id: 'A',
                           target_id: 'B',
                           label: 'connects to'
                         ))

      mermaid = flowchart.to_mermaid
      expect(mermaid).to include('A -- "connects to" --> B')
    end

    it 'escapes special characters' do
      flowchart = described_class.new(direction: 'TD')
      flowchart.add_node(Tasker::Diagram::Node.new(id: 'A', label: 'Node with "quotes"'))
      flowchart.add_node(Tasker::Diagram::Node.new(id: 'B', label: 'Another node'))

      flowchart.add_edge(Tasker::Diagram::Edge.new(
                           source_id: 'A',
                           target_id: 'B',
                           label: 'contains "quoted text"'
                         ))

      mermaid = flowchart.to_mermaid
      expect(mermaid).to include('A["Node with \'quotes\'"]')
      expect(mermaid).to include('-- "contains \'quoted text\'" -->')
    end
  end
end
