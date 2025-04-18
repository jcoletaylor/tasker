# frozen_string_literal: true

module Tasker
  module Diagram
    # Represents an edge (connection) between nodes in a flowchart diagram
    class Edge
      # @return [String] The ID of the source node
      attr_accessor :source_id

      # @return [String] The ID of the target node
      attr_accessor :target_id

      # @return [String] The label to display on the edge
      attr_accessor :label

      # @return [String] The type of edge (e.g., 'solid', 'dashed')
      attr_accessor :type

      # @return [String] Direction of the arrow (e.g., 'forward', 'back', 'both', 'none')
      attr_accessor :direction

      # @return [Hash] Additional attributes for the edge
      attr_accessor :attributes

      # Define constants for style mappings
      EDGE_STYLES = {
        'dashed' => '--',
        'thick' => '==',
        'dotted' => '-.-',
        'solid' => '--' # Default
      }.freeze

      ARROW_STYLES = {
        'back' => '<',
        'both' => '<>',
        'none' => '',
        'forward' => '>' # Default
      }.freeze

      # Creates a new diagram edge
      #
      # @param source_id [String] The ID of the source node
      # @param target_id [String] The ID of the target node
      # @param label [String] The label to display on the edge
      # @param type [String] The type of edge (default: 'solid')
      # @param direction [String] Direction of the arrow (default: 'forward')
      # @param attributes [Hash] Additional attributes for the edge
      # @return [Edge] A new diagram edge
      def initialize(source_id:, target_id:, label: '', type: 'solid', direction: 'forward', attributes: {})
        @source_id = source_id
        @target_id = target_id
        @label = label
        @type = type
        @direction = direction
        @attributes = attributes
      end

      # Convert the edge to a hash representation
      #
      # @return [Hash] Hash representation of the edge
      def to_h
        {
          source_id: source_id,
          target_id: target_id,
          label: label,
          type: type,
          direction: direction,
          attributes: attributes
        }.compact
      end

      # Convert the edge to a JSON string
      #
      # @return [String] JSON representation of the edge
      def to_json(*)
        to_h.to_json(*)
      end

      # Generate Mermaid diagram syntax for this edge
      #
      # @return [String] Mermaid syntax for the edge
      def to_mermaid
        edge_style = EDGE_STYLES[type] || EDGE_STYLES['solid']
        arrow_style = ARROW_STYLES[direction] || ARROW_STYLES['forward']

        label_part = label.empty? ? '' : " \"#{escape_mermaid_text(label)}\""

        # Format the edge in Mermaid syntax
        "#{source_id} #{edge_style}#{label_part} #{edge_style}#{arrow_style} #{target_id}"
      end

      private

      # Escape special characters in Mermaid text
      #
      # @param text [String] The text to escape
      # @return [String] Escaped text safe for Mermaid diagrams
      def escape_mermaid_text(text)
        # Handle nil values
        return '' if text.nil?

        # Replace instances of " with ' to avoid breaking the Mermaid syntax
        text.to_s.tr('"', "'")
      end
    end
  end
end
