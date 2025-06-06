# frozen_string_literal: true

module Tasker
  module Diagram
    # Represents a node in a flowchart diagram
    class Node
      # @return [String] The unique identifier for this node
      attr_accessor :id

      # @return [String] The display label for this node
      attr_accessor :label

      # @return [String] The shape of the node (e.g., 'box', 'circle', 'diamond')
      attr_accessor :shape

      # @return [String] CSS styling for the node
      attr_accessor :style

      # @return [String, nil] URL to link to when clicking the node
      attr_accessor :url

      # @return [Hash] Additional attributes for the node
      attr_accessor :attributes

      # Creates a new diagram node
      #
      # @param id [String] The unique identifier for this node
      # @param label [String] The display label for this node
      # @param shape [String] The shape of the node (default: 'box')
      # @param style [String, nil] CSS styling for the node
      # @param url [String, nil] URL to link to when clicking the node
      # @param attributes [Hash] Additional attributes for the node
      # @return [Node] A new diagram node
      def initialize(id:, label:, shape: 'box', style: nil, url: nil, attributes: {})
        @id = id
        @label = label
        @shape = shape
        @style = style
        @url = url
        @attributes = attributes
      end

      # Convert the node to a hash representation
      #
      # @return [Hash] Hash representation of the node
      def to_h
        {
          id: id,
          label: label,
          shape: shape,
          style: style,
          url: url,
          attributes: attributes
        }.compact
      end

      # Convert the node to a JSON string
      #
      # @return [String] JSON representation of the node
      def to_json(*)
        to_h.to_json(*)
      end

      # Generate Mermaid diagram syntax for this node
      #
      # @return [Array<String>] Array of Mermaid syntax lines for the node
      def to_mermaid
        # Use HTML line breaks in the label
        formatted_label = escape_mermaid_text(label).gsub("\n", '<br/>')

        # Basic node definition
        node_def = "#{id}[\"#{formatted_label}\"]"

        # Add URL link if present
        click_def = url ? "click #{id} \"#{escape_mermaid_text(url)}\"" : nil

        # Add style definition if present
        style_def = style ? "style #{id} #{style}" : nil

        # Return node definition and optional click and style definitions
        [node_def, click_def, style_def].compact
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
