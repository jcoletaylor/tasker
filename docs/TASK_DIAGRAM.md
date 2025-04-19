# Tasker Task Diagrams

The `Tasker::TaskDiagram` class provides a way to visualize task workflows using Mermaid diagrams. This makes it easy to understand the current state of a task's workflow and the relationships between its steps.

## Features

Tasker::TaskDiagram includes:

- A native diagram implementation (no external gems required)
- Automatic color-coding of workflow steps based on their status
- Direct generation of Mermaid syntax for flowcharts
- Support for embedding diagrams in web pages
- Complete HTML document generation with the diagram embedded

## Basic Usage

```ruby
# Create a diagram for a task
task = Tasker::Task.find(task_id)
diagram = Tasker::TaskDiagram.new(task)

# Generate Mermaid syntax
mermaid_string = diagram.to_mermaid

# Generate a complete HTML document with the embedded diagram
html_document = diagram.to_html

# Convert diagram to JSON format
json_data = diagram.to_json
```

## Adding Links to REST Endpoints

You can add clickable links to each workflow step by providing a base URL when creating the diagram:

```ruby
# Create a diagram with links to REST endpoints
base_url = "https://example.com/api"
diagram = Tasker::TaskDiagram.new(task, base_url)

# Each step in the diagram will link to {base_url}/workflow_steps/{workflow_step_id}
```

## Diagram Rendering Options

The TaskDiagram class provides two main methods for visualization:

### to_mermaid

This method returns a string containing the Mermaid diagram syntax, which can be embedded in Markdown files, documentation, or any Mermaid-compatible viewer.

```ruby
diagram = Tasker::TaskDiagram.new(task)
mermaid_string = diagram.to_mermaid

# Example output:
# graph TD
# subgraph "Task 123: MyTask"
#   task_123["Task: MyTask<br/>ID: 123<br/>Status: COMPLETE"]
#   step_456["Step: step1<br/>Status: COMPLETE<br/>Attempts: 1"]
#   task_123 --> step_456
#   ...
# end
```

### to_html

This method returns a complete HTML document with the Mermaid diagram embedded and ready to view in a web browser. The HTML includes:

- The Mermaid JavaScript library for rendering
- Basic styling for the diagram
- Task information in a header section
- The rendered diagram

```ruby
diagram = Tasker::TaskDiagram.new(task)
html = diagram.to_html

# Save to a file for viewing
File.write("task_#{task.task_id}_diagram.html", html)
```

### to_json

This method returns the diagram data as a JSON string with nodes, edges, and diagram properties. This is useful for APIs and for custom rendering.

```ruby
diagram = Tasker::TaskDiagram.new(task)
json = diagram.to_json

# Example output:
# {
#   "nodes": [
#     {"id": "task_123", "label": "Task: MyTask\nID: 123\nStatus: COMPLETE", ...},
#     {"id": "step_456", "label": "Step: step1\nStatus: COMPLETE\nAttempts: 1", ...}
#   ],
#   "edges": [
#     {"source_id": "task_123", "target_id": "step_456", ...}
#   ],
#   "direction": "TD",
#   "title": "Task 123: MyTask"
# }
```

## Templates

The HTML rendering uses an ERB template located in the app/views/tasker/task directory:

- `_diagram.html.erb`: Complete HTML document template for standalone viewing

You can customize this template to match your application's styling and requirements.

## Visual Features

The diagram includes the following visual features:

- Color-coded steps based on their status:
  - PENDING: Light blue
  - IN_PROGRESS: Light green
  - COMPLETE: Green
  - ERROR: Red
  - CANCELLED: Gray

- Task information at the top, including:
  - Task name
  - Task ID
  - Current status

- Step information, including:
  - Step name
  - Status
  - Number of attempts
  - Error information (for steps in ERROR status)

- Directed edges showing the workflow dependencies between steps

## Native Diagram Implementation

The TaskDiagram uses a custom, native diagram implementation with the following components:

### Tasker::Diagram::Node

Represents a node in the diagram with properties like:
- `id`: Unique identifier
- `label`: Display text (supports HTML line breaks with `<br/>`)
- `shape`: Node shape (box, circle, etc.)
- `style`: CSS styling for the node
- `url`: Optional URL for clickable nodes

### Tasker::Diagram::Edge

Represents a connection between nodes with properties like:
- `source_id`: ID of the source node
- `target_id`: ID of the target node
- `label`: Text displayed on the edge (shown within pipes `|` in the syntax)
- `type`: Edge style (solid, dashed, etc.)
- `direction`: Arrow direction (forward, back, both, none)

### Tasker::Diagram::Flowchart

Represents a complete flowchart containing nodes and edges with properties like:
- `nodes`: Collection of nodes
- `edges`: Collection of edges
- `direction`: Layout direction (TD, LR, etc.)
- `title`: Optional title for the diagram (shown as a subgraph title)

All these components support JSON serialization and generation of Mermaid syntax.

## Examples

### Controller Integration

You can easily integrate the task diagram into a controller action:

```ruby
class TasksController < ApplicationController
  def diagram
    @task = Tasker::Task.find(params[:id])
    diagram = Tasker::TaskDiagram.new(@task, request.base_url)

    respond_to do |format|
      format.html { render html: diagram.to_html.html_safe }
      format.text { render plain: diagram.to_mermaid }
      format.json { render json: diagram.to_json }
    end
  end
end
```

### Use in API Responses

```ruby
def show
  task = Tasker::Task.find(params[:id])
  diagram = Tasker::TaskDiagram.new(task, request.base_url)

  render json: {
    task: task.as_json,
    diagram: JSON.parse(diagram.to_json),
    mermaid_syntax: diagram.to_mermaid
  }
end
```

### Use in Rails Views

```erb
<!-- Using a div with Mermaid class -->
<div class="mermaid">
  <%= Tasker::TaskDiagram.new(@task).to_mermaid %>
</div>

<!-- Include the Mermaid JS library in your layout -->
<% content_for :head do %>
  <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
  <script>
    document.addEventListener('DOMContentLoaded', function() {
      mermaid.initialize({ startOnLoad: true });
    });
  </script>
<% end %>
```

### Mermaid Syntax Updates

The current Mermaid syntax follows these conventions:

1. Nodes use HTML line breaks with `<br/>` tags instead of newlines
   ```
   nodeId["Multi-line<br/>content here"]
   ```

2. Edge labels use pipe syntax for clarity
   ```
   A -->|"connects to"| B
   ```

3. Titles are implemented as subgraphs rather than title directives
   ```
   subgraph "Task 123: Process Order"
     // nodes and edges here
   end
   ```

### Customizing the Template

You can modify the template to match your application's styling or add additional information:

```ruby
# Customize the template in:
# app/views/tasker/task/_diagram.html.erb  # Full HTML document
```
