# frozen_string_literal: true

module Tasker
  module Types
    # Represents a single node in a dependency graph
    #
    # A node can represent either a step template (for template graphs)
    # or a workflow step instance (for runtime graphs).
    #
    # @example Template graph node
    #   node = GraphNode.new(
    #     id: 'validate_payment',
    #     name: 'validate_payment',
    #     type: 'step_template',
    #     metadata: { retryable: true, retry_limit: 3 }
    #   )
    #
    # @example Runtime graph node
    #   node = GraphNode.new(
    #     id: '12345',
    #     name: 'validate_payment',
    #     type: 'workflow_step',
    #     state: 'complete',
    #     readiness_status: { ready_for_execution: false },
    #     metadata: { step_class: 'ValidatePaymentStep' }
    #   )
    class GraphNode < Dry::Struct
      transform_keys(&:to_sym)

      # Unique identifier for this node
      # For templates: step name
      # For runtime: step ID as string
      #
      # @!attribute [r] id
      #   @return [String] Node identifier
      attribute :id, Types::String

      # Human-readable name of the node
      #
      # @!attribute [r] name
      #   @return [String] Node name
      attribute :name, Types::String

      # Type of node: 'step_template' or 'workflow_step'
      #
      # @!attribute [r] type
      #   @return [String] Node type
      attribute :type, Types::String

      # Current state (for runtime graphs only)
      #
      # @!attribute [r] state
      #   @return [String, nil] Current state of the step
      attribute? :state, Types::String.optional

      # Readiness status information (for runtime graphs only)
      #
      # @!attribute [r] readiness_status
      #   @return [Hash, nil] Step readiness information
      attribute? :readiness_status, Types::Hash.optional

      # Additional metadata about the node
      #
      # @!attribute [r] metadata
      #   @return [Hash] Node metadata
      attribute :metadata, Types::Hash.default({}.freeze)
    end

    # Represents a relationship between two nodes in a dependency graph
    #
    # @example Basic edge
    #   edge = GraphEdge.new(
    #     from: 'validate_payment',
    #     to: 'update_inventory',
    #     relationship: 'prerequisite'
    #   )
    #
    # @example Edge with metadata
    #   edge = GraphEdge.new(
    #     from: 'step_1',
    #     to: 'step_2',
    #     relationship: 'prerequisite',
    #     metadata: { weight: 1.5, critical_path: true }
    #   )
    class GraphEdge < Dry::Struct
      transform_keys(&:to_sym)

      # Source node identifier
      #
      # @!attribute [r] from
      #   @return [String] Source node ID
      attribute :from, Types::String

      # Target node identifier
      #
      # @!attribute [r] to
      #   @return [String] Target node ID
      attribute :to, Types::String

      # Type of relationship between nodes
      #
      # @!attribute [r] relationship
      #   @return [String] Relationship type
      attribute :relationship, Types::String.default('prerequisite')

      # Additional metadata about the relationship
      #
      # @!attribute [r] metadata
      #   @return [Hash] Edge metadata
      attribute :metadata, Types::Hash.default({}.freeze)
    end

    # Metadata about the overall dependency graph
    #
    # @example Template graph metadata
    #   metadata = GraphMetadata.new(
    #     graph_type: 'template',
    #     handler_name: 'order_processing',
    #     total_nodes: 5,
    #     total_edges: 4
    #   )
    #
    # @example Runtime graph metadata
    #   metadata = GraphMetadata.new(
    #     graph_type: 'runtime',
    #     task_id: '12345',
    #     total_nodes: 5,
    #     total_edges: 4,
    #     execution_context: {
    #       ready_steps: 2,
    #       blocked_steps: 1,
    #       completed_steps: 2
    #     }
    #   )
    class GraphMetadata < Dry::Struct
      transform_keys(&:to_sym)

      # Type of graph: 'template' or 'runtime'
      #
      # @!attribute [r] graph_type
      #   @return [String] Graph type
      attribute :graph_type, Types::String

      # Handler name (for template graphs)
      #
      # @!attribute [r] handler_name
      #   @return [String, nil] Task handler name
      attribute? :handler_name, Types::String.optional

      # Task ID (for runtime graphs)
      #
      # @!attribute [r] task_id
      #   @return [String, nil] Task identifier
      attribute? :task_id, Types::String.optional

      # Total number of nodes in the graph
      #
      # @!attribute [r] total_nodes
      #   @return [Integer] Node count
      attribute :total_nodes, Types::Integer

      # Total number of edges in the graph
      #
      # @!attribute [r] total_edges
      #   @return [Integer] Edge count
      attribute :total_edges, Types::Integer

      # Execution context information (for runtime graphs only)
      #
      # @!attribute [r] execution_context
      #   @return [Hash, nil] Runtime execution information
      attribute? :execution_context, Types::Hash.optional

      # Additional metadata
      #
      # @!attribute [r] additional_data
      #   @return [Hash] Additional graph metadata
      attribute :additional_data, Types::Hash.default({}.freeze)
    end

    # Complete dependency graph structure
    #
    # @example Template dependency graph
    #   graph = DependencyGraph.new(
    #     nodes: [node1, node2],
    #     edges: [edge1],
    #     metadata: template_metadata
    #   )
    #
    # @example Runtime dependency graph
    #   graph = DependencyGraph.new(
    #     nodes: [runtime_node1, runtime_node2],
    #     edges: [runtime_edge1],
    #     metadata: runtime_metadata
    #   )
    class DependencyGraph < BaseConfig
      transform_keys(&:to_sym)

      # All nodes in the dependency graph
      #
      # @!attribute [r] nodes
      #   @return [Array<GraphNode>] Graph nodes
      attribute :nodes, Types::Array.of(GraphNode)

      # All edges in the dependency graph
      #
      # @!attribute [r] edges
      #   @return [Array<GraphEdge>] Graph edges
      attribute :edges, Types::Array.of(GraphEdge)

      # Metadata about the overall graph
      #
      # @!attribute [r] metadata
      #   @return [GraphMetadata] Graph metadata
      attribute :metadata, GraphMetadata

      def initialize(*args)
        super(*args)
        # Explicitly freeze arrays for immutability
        nodes.freeze
        edges.freeze
      end
    end
  end
end
