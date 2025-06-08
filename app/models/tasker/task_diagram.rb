# frozen_string_literal: true

require 'erb'
require 'pathname'

module Tasker
  class TaskDiagram
    # Colors for different step statuses
    STATUS_COLORS = {
      Tasker::Constants::WorkflowStepStatuses::PENDING => 'lightblue',
      Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS => 'lightgreen',
      Tasker::Constants::WorkflowStepStatuses::COMPLETE => 'green',
      Tasker::Constants::WorkflowStepStatuses::ERROR => 'red',
      Tasker::Constants::WorkflowStepStatuses::CANCELLED => 'gray'
    }.freeze

    # Create a new task diagram
    #
    # @param task [Tasker::Task] The task to create a diagram for
    # @param base_url [String, nil] Optional base URL for REST endpoints
    # @return [TaskDiagram] A new task diagram instance
    def initialize(task, base_url = nil)
      @task = task
      @base_url = base_url
    end

    # Generate a Mermaid diagram string for the task
    #
    # @return [String] Mermaid flowchart diagram string
    delegate :to_mermaid, to: :flowchart

    # Generate a complete HTML document with embedded Mermaid diagram
    #
    # @return [String] HTML document with Mermaid diagram
    def to_html
      # Generate the mermaid diagram
      @diagram = flowchart.to_mermaid

      # Create binding with relevant variables
      task = @task # Make task available to the template
      diagram = @diagram # Make diagram available to the template

      # Create a binding with the variables
      b = binding

      # Get the template path relative to this file
      template_path = views_path.join('_diagram.html.erb')

      # Load and render the template with ERB
      begin
        template = File.read(template_path)
        ERB.new(template).result(b)
      rescue Errno::ENOENT
        raise TaskDiagramError, "Template file not found: #{template_path}"
      rescue Errno::EACCES
        raise TaskDiagramError, "Permission denied while accessing template file: #{template_path}"
      end
    end

    def to_json(pretty: false)
      flowchart.to_json(pretty: pretty)
    end

    private

    def flowchart
      return @flowchart if @flowchart

      # Preload workflow steps with scenic view relationships for efficiency
      workflow_steps = @task.workflow_steps.includes(:named_step, :step_dag_relationship)

      # Create a new flowchart
      @flowchart = Tasker::Diagram::Flowchart.new(
        direction: 'TD',
        title: "Task #{@task.task_id}: #{@task.name}"
      )

      # Add task info node
      @flowchart.add_node(build_task_node)

      # Build nodes for all workflow steps
      workflow_steps.each do |step|
        @flowchart.add_node(build_step_node(step))
      end

      # Build all edges efficiently using scenic view data
      build_all_step_edges(workflow_steps).each do |edge|
        @flowchart.add_edge(edge)
      end

      @flowchart
    end

    # Get the path to the view templates directory
    #
    # @return [Pathname] Path to view templates
    def views_path
      # Get the absolute path of the current file
      current_file = Pathname.new(__FILE__)

      # Navigate to the views directory relative to this file
      # This file is in app/models/tasker/task_diagram.rb
      # Views are in app/views/tasker/task/
      current_file.dirname.parent.parent.parent.join('app', 'views', 'tasker', 'task')
    end

    # Build the task information node
    #
    # @return [Tasker::Diagram::Node] The task node
    def build_task_node
      Tasker::Diagram::Node.new(
        id: "task_#{@task.task_id}",
        label: "Task: #{@task.name}\nID: #{@task.task_id}\nStatus: #{@task.status}"
      )
    end

    # Build a node for a workflow step
    #
    # @param step [Tasker::WorkflowStep] The workflow step
    # @return [Tasker::Diagram::Node] The step node
    def build_step_node(step)
      node_id = "step_#{step.workflow_step_id}"
      color = STATUS_COLORS[step.status] || 'lightgray'

      # Create label with step details
      label = build_step_label(step)

      # Create clickable URL if base_url is provided
      url = @base_url ? "#{@base_url}/tasks/#{@task.task_id}/workflow_steps/#{step.workflow_step_id}" : nil

      # Create node with styling
      Tasker::Diagram::Node.new(
        id: node_id,
        label: label.join("\n"),
        shape: 'box',
        style: "fill:#{color};",
        url: url
      )
    end

    # Build the label lines for a step node
    #
    # @param step [Tasker::WorkflowStep] The workflow step
    # @return [Array<String>] Array of label lines
    def build_step_label(step)
      label = [
        "Step: #{step.name}",
        "Status: #{step.status}",
        "Attempts: #{step.attempts || 0}"
      ]

      # Add error info if applicable
      if step.status == Tasker::Constants::WorkflowStepStatuses::ERROR && step.results&.key?('error')
        error_msg = step.results['error'].to_s
        # Truncate long error messages
        error_msg = "#{error_msg[0..27]}..." if error_msg.length > 30
        label << "Error: #{error_msg}"
      end

      label
    end

    # Build an edge between two nodes
    #
    # @param source_id [String] The source node ID
    # @param target_id [String] The target node ID
    # @param label [String] The edge label
    # @return [Tasker::Diagram::Edge] The edge
    def build_edge(source_id, target_id, label = '')
      Tasker::Diagram::Edge.new(
        source_id: source_id,
        target_id: target_id,
        label: label
      )
    end

    # Build all edges efficiently using scenic view data - eliminates N+1 queries
    #
    # @param workflow_steps [Array<Tasker::WorkflowStep>] All workflow steps for the task
    # @return [Array<Tasker::Diagram::Edge>] All edges for the diagram
    def build_all_step_edges(workflow_steps)
      edges = []

      # Add edges from task to root steps using dedicated builder
      edges.concat(TaskToRootStepEdgeBuilder.build(@task, workflow_steps))

      # Add edges between steps using dedicated builder
      edges.concat(StepToStepEdgeBuilder.build(workflow_steps))

      edges
    end

    # Service class to build edges from task to root steps
    # Reduces complexity by organizing edge building logic
    class TaskToRootStepEdgeBuilder
      class << self
        # Build edges from task node to root steps
        #
        # @param task [Tasker::Task] The task
        # @param workflow_steps [Array<Tasker::WorkflowStep>] All workflow steps
        # @return [Array<Tasker::Diagram::Edge>] Task to root step edges
        def build(task, workflow_steps)
          edges = []

          workflow_steps.each do |step|
            next unless step.step_dag_relationship&.is_root_step

            edges << build_edge(
              "task_#{task.task_id}",
              "step_#{step.workflow_step_id}"
            )
          end

          edges
        end

        private

        # Build an edge between two nodes
        #
        # @param source_id [String] The source node ID
        # @param target_id [String] The target node ID
        # @param label [String] The edge label
        # @return [Tasker::Diagram::Edge] The edge
        def build_edge(source_id, target_id, label = '')
          Tasker::Diagram::Edge.new(
            source_id: source_id,
            target_id: target_id,
            label: label
          )
        end
      end
    end

    # Service class to build edges between workflow steps
    # Reduces complexity by organizing edge building logic
    class StepToStepEdgeBuilder
      class << self
        # Build edges between workflow steps
        #
        # @param workflow_steps [Array<Tasker::WorkflowStep>] All workflow steps
        # @return [Array<Tasker::Diagram::Edge>] Step to step edges
        def build(workflow_steps)
          edge_data = collect_edge_data(workflow_steps)
          return [] if edge_data.empty?

          edge_records = batch_load_edge_records(edge_data)
          build_edges_from_data(edge_data, edge_records)
        end

        private

        # Collect all edge relationships for efficient batch lookup
        #
        # @param workflow_steps [Array<Tasker::WorkflowStep>] All workflow steps
        # @return [Array<Hash>] Edge data with from_step_id and to_step_id
        def collect_edge_data(workflow_steps)
          edge_data = []

          workflow_steps.each do |step|
            next unless step.step_dag_relationship

            child_ids = step.step_dag_relationship.child_step_ids_array
            child_ids.each do |child_id|
              edge_data << {
                from_step_id: step.workflow_step_id,
                to_step_id: child_id
              }
            end
          end

          edge_data
        end

        # Batch load all WorkflowStepEdge records for edge labels
        #
        # @param edge_data [Array<Hash>] Edge data to load records for
        # @return [Hash] Hash mapping edge keys to edge records
        def batch_load_edge_records(edge_data)
          edge_records = {}

          conditions = edge_data.map do |data|
            "(from_step_id = #{data[:from_step_id]} AND to_step_id = #{data[:to_step_id]})"
          end

          Tasker::WorkflowStepEdge.where(conditions.join(' OR ')).find_each do |edge_record|
            key = "#{edge_record.from_step_id}_#{edge_record.to_step_id}"
            edge_records[key] = edge_record
          end

          edge_records
        end

        # Build edges using pre-calculated data and records
        #
        # @param edge_data [Array<Hash>] Edge data with IDs
        # @param edge_records [Hash] Loaded edge records for labels
        # @return [Array<Tasker::Diagram::Edge>] Built edges
        def build_edges_from_data(edge_data, edge_records)
          edges = []

          edge_data.each do |data|
            source_id = "step_#{data[:from_step_id]}"
            target_id = "step_#{data[:to_step_id]}"

            # Find edge label from batch-loaded records
            key = "#{data[:from_step_id]}_#{data[:to_step_id]}"
            edge_label = edge_records[key]&.name || ''

            edges << build_edge(source_id, target_id, edge_label)
          end

          edges
        end

        # Build an edge between two nodes
        #
        # @param source_id [String] The source node ID
        # @param target_id [String] The target node ID
        # @param label [String] The edge label
        # @return [Tasker::Diagram::Edge] The edge
        def build_edge(source_id, target_id, label = '')
          Tasker::Diagram::Edge.new(
            source_id: source_id,
            target_id: target_id,
            label: label
          )
        end
      end
    end
  end
end
