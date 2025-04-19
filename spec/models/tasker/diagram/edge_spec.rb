# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Diagram::Edge do
  describe 'basic functionality' do
    let(:edge) do
      described_class.new(
        source_id: 'A',
        target_id: 'B',
        label: 'connects to',
        type: 'solid',
        direction: 'forward',
        attributes: { weight: 5 }
      )
    end

    it 'initializes with correct attributes' do
      expect(edge.source_id).to eq('A')
      expect(edge.target_id).to eq('B')
      expect(edge.label).to eq('connects to')
      expect(edge.type).to eq('solid')
      expect(edge.direction).to eq('forward')
      expect(edge.attributes).to eq(weight: 5)
    end

    it 'converts to hash' do
      hash = edge.to_h
      expect(hash[:source_id]).to eq('A')
      expect(hash[:target_id]).to eq('B')
      expect(hash[:label]).to eq('connects to')
      expect(hash[:type]).to eq('solid')
      expect(hash[:direction]).to eq('forward')
      expect(hash[:attributes]).to eq(weight: 5)
    end

    it 'converts to JSON' do
      json = edge.to_json
      expect(json).to be_a(String)
      parsed = JSON.parse(json)
      expect(parsed['source_id']).to eq('A')
      expect(parsed['target_id']).to eq('B')
      expect(parsed['label']).to eq('connects to')
    end
  end

  describe '#to_mermaid' do
    it 'generates basic edge syntax' do
      edge = described_class.new(source_id: 'A', target_id: 'B')
      expect(edge.to_mermaid).to eq('A --> B')
    end

    it 'includes label when provided' do
      edge = described_class.new(source_id: 'A', target_id: 'B', label: 'connects to')
      expect(edge.to_mermaid).to eq('A -->|"connects to"| B')
    end

    it 'escapes quotes in labels' do
      edge = described_class.new(source_id: 'A', target_id: 'B', label: 'with "quotes"')
      expect(edge.to_mermaid).to eq('A -->|"with \'quotes\'"| B')
    end

    it 'handles empty labels' do
      edge = described_class.new(source_id: 'A', target_id: 'B', label: '')
      expect(edge.to_mermaid).to eq('A --> B')
    end

    it 'handles nil labels' do
      edge = described_class.new(source_id: 'A', target_id: 'B', label: nil)
      expect(edge.to_mermaid).to eq('A --> B')
    end
  end
end
