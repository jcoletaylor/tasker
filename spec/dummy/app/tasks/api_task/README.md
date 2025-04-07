# API Integration Task Example

This example demonstrates a robust task handling system for e-commerce order processing, featuring retryable steps, type safety, and event-driven architecture.

## Workflow Overview

The task processes an e-commerce order through the following steps:

```mermaid
graph TD
    A[Start] --> B[Fetch Cart]
    A --> C[Fetch Products]
    B --> D[Validate Products]
    C --> D
    D --> E[Create Order]
    E --> F[Publish Event]
    F --> G[Complete]

    style B fill:#e8e8e8,stroke:#666666
    style C fill:#e8e8e8,stroke:#666666
    style D fill:#d8d8d8,stroke:#666666
    style E fill:#c8c8c8,stroke:#444444
    style F fill:#b8b8b8,stroke:#444444
    style G fill:#a8a8a8,stroke:#444444
```

### Step Details

1. **Fetch Cart**
   - Retrieves cart details by ID from the e-commerce system
   - Validates cart existence
   - Returns cart with products and quantities

2. **Fetch Products**
   - Retrieves all available products from the product catalog
   - Returns complete product details including stock levels

3. **Validate Products**
   - Matches cart products with product catalog
   - Validates product existence and availability
   - Returns validated product list

4. **Create Order**
   - Calculates order totals (including discounts)
   - Creates order with validated products
   - Sets initial order status

5. **Publish Event**
   - Publishes order creation event to message queue
   - Handles event publishing confirmation

## System Architecture

### Key Components

1. **Task Handler System**
   - Manages task lifecycle and execution
   - Handles step dependencies and sequencing
   - Provides retry mechanisms for failed steps

2. **Data Models**
   - `Api::Cart`: Represents shopping cart with products
   - `Api::Product`: Represents product details
   - `ExampleOrder`: Represents created order

3. **Type System**
   - Uses `dry-struct` for type-safe data structures
   - Implements coercible types for data validation
   - Provides default values for optional fields

4. **Event System**
   - Handles asynchronous event publishing
   - Manages event confirmation and status
   - Supports event subscription

### Workflow & Retry Mechanism

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

## Usage Example

```ruby
# Create a task request
task_request = Tasker::Types::TaskRequest.new(
  name: 'api_integration_task',
  context: { cart_id: 1 },
  initiator: 'user',
  reason: 'Process order',
  source_system: 'web'
)

# Initialize and execute task
task_handler = ApiTask::IntegrationExample.new
task = task_handler.initialize_task!(task_request)
task_handler.handle(task)
```

## Testing

The implementation includes comprehensive tests:

- Unit tests for each step handler
- Integration tests for the complete workflow
- Error case handling and validation
- Retry mechanism verification

Run tests with:

```bash
bundle exec rspec spec/examples/api_task/integration_example_spec.rb
```
