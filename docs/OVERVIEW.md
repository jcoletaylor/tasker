# System Overview

## Example of a Configured Task Handler

Here's an example YAML file for an e-commerce API integration task handler:

```yaml
---
name: api_task/integration_yaml_example
module_namespace: ApiTask
task_handler_class: IntegrationYamlExample
concurrent: true

default_dependent_system: ecommerce_system

named_steps:
  - fetch_cart
  - fetch_products
  - validate_products
  - create_order
  - publish_event

schema:
  type: object
  required:
    - cart_id
  properties:
    cart_id:
      type: integer

step_templates:
  - name: fetch_cart
    description: Fetch cart details from e-commerce system
    handler_class: ApiTask::StepHandler::CartFetchStepHandler
    handler_config:
      type: api
      url: https://api.ecommerce.com/cart
      params:
        cart_id: 1

  - name: fetch_products
    description: Fetch product details from product catalog
    handler_class: ApiTask::StepHandler::ProductsFetchStepHandler
    handler_config:
      type: api
      url: https://api.ecommerce.com/products

  - name: validate_products
    description: Validate product availability
    depends_on_steps:
      - fetch_products
      - fetch_cart
    handler_class: ApiTask::StepHandler::ProductsValidateStepHandler

  - name: create_order
    description: Create order from validated cart
    depends_on_step: validate_products
    handler_class: ApiTask::StepHandler::CreateOrderStepHandler

  - name: publish_event
    description: Publish order created event
    depends_on_step: create_order
    handler_class: ApiTask::StepHandler::PublishEventStepHandler

environments:
  development:
    step_templates:
      - name: fetch_cart
        handler_config:
          url: http://localhost:3000/api/cart
          params:
            cart_id: 1
            debug: true

      - name: fetch_products
        handler_config:
          url: http://localhost:3000/api/products
          params:
            debug: true

  test:
    step_templates:
      - name: fetch_cart
        handler_config:
          url: http://test-api.ecommerce.com/cart
          params:
            cart_id: 1
            test_mode: true

      - name: fetch_products
        handler_config:
          url: http://test-api.ecommerce.com/products
          params:
            test_mode: true

  production:
    step_templates:
      - name: fetch_cart
        handler_config:
          url: https://api.ecommerce.com/cart
          params:
            cart_id: 1
            api_key: ${ECOMMERCE_API_KEY}

      - name: fetch_products
        handler_config:
          url: https://api.ecommerce.com/products
          params:
            api_key: ${ECOMMERCE_API_KEY}
```

## Environment-Specific Configuration

Tasker supports environment-specific configuration overrides in YAML files. This allows you to:

1. Define a base configuration that works across all environments
2. Override specific settings for each environment (development, test, production)

The configuration is merged at runtime, with environment-specific settings taking precedence over the base configuration. This is particularly useful for:

- Using different API endpoints per environment
- Enabling debug mode in development
- Using test mode in test environments

To use environment-specific configuration:

1. Add environment-specific sections to your YAML file
2. Override only the settings that need to change per environment
3. The TaskBuilder will automatically merge the configurations based on the current Rails environment

## API Task Example

See the [spec/dummy/app/tasks/api_task](./spec/dummy/app/tasks/api_task) directory for an example of a task handler that processes an e-commerce order through a series of steps, interacting with external systems, and handling errors and retries. You can read more about the example [here](./spec/dummy/app/tasks/api_task/README.md).

### API Routes

Tasker provides a RESTful API for managing tasks. Here are the available endpoints:

#### Tasks

- `GET /tasker/tasks` - List all tasks
- `POST /tasker/tasks` - Create and enqueue a new task
- `GET /tasker/tasks/{task_id}` - Get task details
- `PATCH/PUT /tasker/tasks/{task_id}` - Update task
- `DELETE /tasker/tasks/{task_id}` - Cancel task

#### Workflow Steps

- `GET /tasker/tasks/{task_id}/workflow_steps` - List steps for a task
- `GET /tasker/tasks/{task_id}/workflow_steps/{step_id}` - Get step details
- `PATCH/PUT /tasker/tasks/{task_id}/workflow_steps/{step_id}` - Update step
- `DELETE /tasker/tasks/{task_id}/workflow_steps/{step_id}` - Cancel step

#### Task Diagrams

- `GET /tasker/tasks/{task_id}/diagram` - Get a diagram for a task

### Creating a Task via API

Example of creating a task using curl:

```bash
curl -X POST https://www.example.com/tasker/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "name": "api_integration_task",
    "context": {
      "cart_id": 123
    },
    "initiator": "web_interface",
    "reason": "Process new order",
    "source_system": "ecommerce",
    "tags": ["order_processing", "api_integration"]
  }'
```

The request body must include:

- `name`: The name of the task handler to use
- `context`: A JSON object containing the task's context data
- `initiator`: Who/what initiated the task
- `reason`: Why the task was created
- `source_system`: The system that created the task
- `tags`: (Optional) Array of tags for categorization

## Workflow & Retry Mechanism

```mermaid
graph TD
    Start([Task Initialization]) --> FindRoots[Find Root Steps]
    FindRoots --> QueueRoots[Queue Root Steps]
    QueueRoots --> ParallelExec{Parallel Execution}

    ParallelExec --> RootA[Root Step A]
    ParallelExec --> RootB[Root Step B]

    RootA --> |Running| A[Step Ready for Execution]
    RootB --> |Running| A

    A --> B{Step Succeeded?}
    B -->|Yes| C[Mark Step Complete]
    B -->|No| D{Retryable Error?}
    D -->|No| E[Mark as Failed]
    D -->|Yes| F{Attempts < Max?}
    F -->|No| E
    F -->|Yes| G[Calculate Backoff]

    G --> H[Apply Exponential Backoff with Jitter]
    H --> I[Wait for Backoff Period]
    I --> J[Increment Attempt Count]
    J --> A

    C --> K{Find Dependent Steps}
    K --> DepCheck{For Each Dependent Step}
    DepCheck --> DependenciesMet{All Dependencies\nComplete?}
    DependenciesMet -->|Yes| QueueStep[Queue Step for Execution]
    QueueStep --> ParallelExec
    DependenciesMet -->|No| Wait[Step Remains Pending]

    E --> TaskCheck{Any Step\nFailed?}
    TaskCheck -->|Yes| FailTask[Mark Task as Failed]

    Wait -.- DepMonitor[Dependency Monitor]
    DepMonitor -.- DependenciesMet

    C --> CompleteCheck{All Steps\nComplete?}
    CompleteCheck -->|Yes| CompleteTask[Mark Task as Complete]
    CompleteCheck -->|No| Continue[Continue Processing]

    subgraph DAG Traversal
    FindRoots
    QueueRoots
    ParallelExec
    RootA
    RootB
    K
    DepCheck
    DependenciesMet
    QueueStep
    Wait
    DepMonitor
    end

    subgraph Exponential Backoff
    G
    H
    I
    J
    end

    subgraph Task Status Management
    E
    TaskCheck
    FailTask
    CompleteCheck
    CompleteTask
    end

    %% Initialize with dark borders and light fills
    style Start fill:#ffffff,stroke:#444444,stroke-width:2px
    style FindRoots fill:#f6f6f6,stroke:#444444
    style QueueRoots fill:#f6f6f6,stroke:#444444
    style ParallelExec fill:#f6f6f6,stroke:#444444,stroke-width:2px

    %% Root steps (slightly lighter gray)
    style RootA fill:#e8e8e8,stroke:#666666
    style RootB fill:#e8e8e8,stroke:#666666

    %% Standard flow components (white with medium gray borders)
    style A fill:#ffffff,stroke:#666666
    style B fill:#ffffff,stroke:#666666
    style C fill:#ffffff,stroke:#666666
    style D fill:#ffffff,stroke:#666666
    style F fill:#ffffff,stroke:#666666
    style CompleteCheck fill:#ffffff,stroke:#666666
    style Continue fill:#ffffff,stroke:#666666
    style TaskCheck fill:#ffffff,stroke:#666666

    %% Exponential backoff (light gray)
    style G fill:#f0f0f0,stroke:#666666
    style H fill:#f0f0f0,stroke:#666666
    style I fill:#f0f0f0,stroke:#666666
    style J fill:#f0f0f0,stroke:#666666

    %% DAG specific components (slightly darker gray)
    style K fill:#e0e0e0,stroke:#444444
    style DepCheck fill:#e0e0e0,stroke:#444444
    style DependenciesMet fill:#e0e0e0,stroke:#444444,stroke-width:2px
    style QueueStep fill:#e0e0e0,stroke:#444444
    style Wait fill:#e0e0e0,stroke:#444444,stroke-dasharray: 5 5
    style DepMonitor fill:#e0e0e0,stroke:#444444,stroke-dasharray: 5 5

    %% Success and failure states (dark and medium grays)
    style CompleteTask fill:#d0d0d0,stroke:#222222,stroke-width:2px
    style FailTask fill:#b0b0b0,stroke:#222222,stroke-width:2px
    style E fill:#b0b0b0,stroke:#222222
```

The system implements advanced workflow traversal with parallel execution and sophisticated retry logic:

- **DAG Traversal & Parallel Execution**
  - Initial identification and queueing of root steps (no dependencies)
  - Parallel execution of independent steps at each level
  - Dynamic discovery of next executable steps as dependencies are satisfied
  - Continuous monitoring of dependency status to activate pending steps
  - Automatic task completion detection when all steps are finished

- **Industry Standard Exponential Backoff**
  - Base delay that doubles with each attempt: `base_delay * (2^attempt)`
  - Random jitter to prevent thundering herd problems
  - Configurable maximum delay cap (30 seconds)
  - Respects server-provided Retry-After headers when available

- **Task Status Management**
  - Real-time monitoring of all step statuses
  - Early failure detection and propagation
  - Graceful handling of unrecoverable errors
