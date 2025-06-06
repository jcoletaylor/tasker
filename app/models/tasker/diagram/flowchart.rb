# frozen_string_literal: true

module Tasker
  module Diagram
    # Represents a flowchart diagram with nodes and edges
    class Flowchart
      # @return [Array<Tasker::Diagram::Node>] The nodes in the flowchart
      attr_accessor :nodes

      # @return [Array<Tasker::Diagram::Edge>] The edges in the flowchart
      attr_accessor :edges

      # @return [String] The direction of the flowchart (TD: top-down, LR: left-right, etc.)
      attr_accessor :direction

      # @return [String] The title of the flowchart
      attr_accessor :title

      # @return [Hash] Additional attributes for the flowchart
      attr_accessor :attributes

      # Creates a new flowchart diagram
      #
      # @param nodes [Array<Tasker::Diagram::Node>] The nodes in the flowchart
      # @param edges [Array<Tasker::Diagram::Edge>] The edges in the flowchart
      # @param direction [String] The direction of the flowchart (default: 'TD')
      # @param title [String, nil] The title of the flowchart
      # @param attributes [Hash] Additional attributes for the flowchart
      # @return [Flowchart] A new flowchart diagram
      def initialize(nodes: [], edges: [], direction: 'TD', title: nil, attributes: {})
        @nodes = nodes
        @edges = edges
        @direction = direction
        @title = title
        @attributes = attributes
      end

      # Add a node to the flowchart
      #
      # @param node [Tasker::Diagram::Node] The node to add
      # @return [Tasker::Diagram::Node] The added node
      def add_node(node)
        @nodes << node
        node
      end

      # Add an edge to the flowchart
      #
      # @param edge [Tasker::Diagram::Edge] The edge to add
      # @return [Tasker::Diagram::Edge] The added edge
      def add_edge(edge)
        @edges << edge
        edge
      end

      # Find a node by its ID
      #
      # @param id [String] The ID of the node to find
      # @return [Tasker::Diagram::Node, nil] The node with the given ID, or nil if not found
      def find_node(id)
        @nodes.find { |node| node.id == id }
      end

      # Find all edges connected to a node
      #
      # @param node_id [String] The ID of the node
      # @param direction [Symbol] :outgoing, :incoming, or :both (default: :both)
      # @return [Array<Tasker::Diagram::Edge>] The edges connected to the node
      def find_edges_for_node(node_id, direction = :both)
        case direction
        when :outgoing
          @edges.select { |edge| edge.source_id == node_id }
        when :incoming
          @edges.select { |edge| edge.target_id == node_id }
        else
          @edges.select { |edge| edge.source_id == node_id || edge.target_id == node_id }
        end
      end

      # Convert the flowchart to a hash representation
      #
      # @return [Hash] Hash representation of the flowchart
      def to_h
        {
          nodes: nodes.map(&:to_h),
          edges: edges.map(&:to_h),
          direction: direction,
          title: title,
          attributes: attributes
        }.compact
      end

      # Convert the flowchart to a JSON string
      #
      # @return [String] JSON representation of the flowchart
      def to_json(*)
        to_h.to_json(*)
      end

      # Generate Mermaid diagram syntax for this flowchart
      #
      # @return [String] Mermaid syntax for the flowchart
      def to_mermaid
        lines = []

        # Add the flowchart definition
        lines << "graph #{direction}"

        # Use a subgraph with title if title is present
        if title
          lines << "subgraph \"#{title}\""
          indent = '  '
        else
          indent = ''
        end

        # Add all nodes
        nodes.each do |node|
          node.to_mermaid.each do |line|
            lines << "#{indent}#{line}"
          end
        end

        # Add all edges
        edges.each do |edge|
          lines << "#{indent}#{edge.to_mermaid}"
        end

        # Close the subgraph if we have a title
        lines << 'end' if title

        # Join all lines with newlines
        lines.join("\n")
      end
    end
  end
end
