# typed: false
# frozen_string_literal: true

require_relative 'application_controller'

module Tasker
  class HandlersController < ApplicationController
    before_action :set_handler_factory

    # GET /handlers - List all namespaces
    def index
      render json: {
        namespaces: @handler_factory.registered_namespaces.map do |namespace|
          {
            name: namespace.to_s,
            handler_count: count_handlers_in_namespace(namespace)
          }
        end,
        total_namespaces: @handler_factory.registered_namespaces.size
      }, status: :ok
    end

    # GET /handlers/:namespace - List handlers in a specific namespace
    def show_namespace
      namespace_name = params[:namespace]

      unless @handler_factory.registered_namespaces.include?(namespace_name.to_sym)
        render json: { error: 'Namespace not found' }, status: :not_found
        return
      end

      namespace_handlers = @handler_factory.list_handlers(namespace: namespace_name)

      handlers_data = namespace_handlers.map do |handler_name, versions|
        {
          name: handler_name,
          namespace: namespace_name,
          versions: versions.keys.sort,
          latest_version: versions.keys.max,
          handler_count: versions.size
        }
      end

      render json: {
        namespace: namespace_name,
        handlers: handlers_data,
        total_handlers: handlers_data.size
      }, status: :ok
    end

    # GET /handlers/:namespace/:name - Show specific handler with dependency graph
    def show
      namespace_name = params[:namespace]
      handler_name = params[:name]
      version = params[:version] || '0.1.0'

      unless @handler_factory.registered_namespaces.include?(namespace_name.to_sym)
        render json: { error: 'Namespace not found' }, status: :not_found
        return
      end

      handler_data = find_handler_data(namespace_name, handler_name, version)

      if handler_data
        # Add dependency graph information
        handler_data[:dependency_graph] = build_dependency_graph(handler_data[:step_templates])
        render json: { handler: handler_data }, status: :ok
      else
        render json: { error: 'Handler not found in namespace' }, status: :not_found
      end
    end

    private

    def set_handler_factory
      @handler_factory = Tasker::HandlerFactory.instance
    end

    def count_handlers_in_namespace(namespace)
      namespace_handlers = @handler_factory.list_handlers(namespace: namespace)
      namespace_handlers.size
    end

    def find_handler_data(namespace_name, handler_name, version)
      # Get all versions for this handler in the namespace
      namespace_handlers = @handler_factory.list_handlers(namespace: namespace_name)
      handler_versions = namespace_handlers[handler_name.to_sym]

      return nil unless handler_versions

      # Determine the actual version to use
      actual_version = if version == 'latest'
                         handler_versions.keys.max
                       elsif version == '0.1.0' && !handler_versions.key?('0.1.0')
                         # Fall back to lowest available version if 0.1.0 doesn't exist
                         handler_versions.keys.min
                       else
                         version
                       end

      # Get the handler class for the specific version
      handler_class = handler_versions[actual_version]
      return nil unless handler_class

      # Use the HandlerSerializer to get consistent data structure
      serializer = Tasker::HandlerSerializer.new(
        handler_class,
        handler_name: handler_name,
        namespace: namespace_name,
        version: actual_version
      )
      serializer.serializable_hash
    end

    def build_dependency_graph(step_templates)
      return { nodes: [], edges: [] } unless step_templates.is_a?(Array)

      nodes = []
      edges = []

      step_templates.each do |step|
        # Add node for this step
        nodes << {
          id: step[:name],
          name: step[:name],
          type: 'step',
          handler_class: step[:handler_class],
          configuration: step[:configuration] || step[:handler_config] || {}
        }

        # Add edge if this step depends on another
        next unless step[:depends_on_step]

        edges << {
          from: step[:depends_on_step],
          to: step[:name],
          type: 'dependency'
        }
      end

      {
        nodes: nodes,
        edges: edges,
        execution_order: calculate_execution_order(step_templates)
      }
    end

    def calculate_execution_order(step_templates)
      # Simple topological sort to determine execution order
      steps_by_name = step_templates.index_by { |step| step[:name] }
      visited = Set.new
      order = []

      def visit_step(step_name, steps_by_name, visited, order)
        return if visited.include?(step_name)

        step = steps_by_name[step_name]
        return unless step

        # Visit dependencies first
        visit_step(step[:depends_on_step], steps_by_name, visited, order) if step[:depends_on_step]

        visited.add(step_name)
        order << step_name
      end

      steps_by_name.each_key do |step_name|
        visit_step(step_name, steps_by_name, visited, order)
      end

      order
    end
  end
end
