# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Diagram::Node do
  describe 'basic functionality' do
    let(:node) do
      described_class.new(
        id: 'test-node',
        label: 'Test Node',
        shape: 'box',
        style: 'fill:blue;stroke:green;',
        url: 'https://example.com',
        attributes: { priority: 'high' }
      )
    end

    it 'initializes with correct attributes' do
      expect(node.id).to eq('test-node')
      expect(node.label).to eq('Test Node')
      expect(node.shape).to eq('box')
      expect(node.style).to eq('fill:blue;stroke:green;')
      expect(node.url).to eq('https://example.com')
      expect(node.attributes).to eq(priority: 'high')
    end

    it 'converts to hash' do
      hash = node.to_h
      expect(hash[:id]).to eq('test-node')
      expect(hash[:label]).to eq('Test Node')
      expect(hash[:shape]).to eq('box')
      expect(hash[:style]).to eq('fill:blue;stroke:green;')
      expect(hash[:url]).to eq('https://example.com')
      expect(hash[:attributes]).to eq(priority: 'high')
    end

    it 'converts to JSON' do
      json = node.to_json
      expect(json).to be_a(String)
      parsed = JSON.parse(json)
      expect(parsed['id']).to eq('test-node')
      expect(parsed['label']).to eq('Test Node')
      expect(parsed['shape']).to eq('box')
    end
  end

  describe '#to_mermaid' do
    it 'generates basic node syntax' do
      node = described_class.new(id: 'A', label: 'Test Node')
      result = node.to_mermaid
      expect(result).to include('A["Test Node"]')
    end

    it 'includes styling when provided' do
      node = described_class.new(
        id: 'A',
        label: 'Styled Node',
        style: 'fill:red;stroke:blue;'
      )
      result = node.to_mermaid
      expect(result).to include('A["Styled Node"]')
      expect(result).to include('style A fill:red;stroke:blue;')
    end

    it 'includes URL when provided' do
      node = described_class.new(
        id: 'A',
        label: 'Clickable Node',
        url: 'https://example.com'
      )
      result = node.to_mermaid
      expect(result).to include('A["Clickable Node"]')
      expect(result).to include('click A "https://example.com"')
    end

    it 'escapes quotes in labels' do
      node = described_class.new(id: 'A', label: 'Node with "quotes"')
      result = node.to_mermaid
      expect(result).to include('A["Node with \'quotes\'"]')
    end

    it 'converts newlines to HTML breaks' do
      node = described_class.new(id: 'A', label: "Line 1\nLine 2\nLine 3")
      result = node.to_mermaid
      expect(result).to include('A["Line 1<br/>Line 2<br/>Line 3"]')
    end

    it 'returns an array of strings' do
      node = described_class.new(
        id: 'A',
        label: 'Test Node',
        style: 'fill:blue;',
        url: 'https://example.com'
      )
      result = node.to_mermaid
      expect(result).to be_an(Array)
      expect(result.size).to eq(3) # Node def, click def, style def
      expect(result[0]).to eq('A["Test Node"]')
      expect(result[1]).to eq('click A "https://example.com"')
      expect(result[2]).to eq('style A fill:blue;')
    end
  end
end
