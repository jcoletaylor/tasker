# Workflow & Retry Mechanism

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

The system implements advanced workflow traversal with parallel execution, sophisticated retry logic, and comprehensive event-driven observability:

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

- **Event-Driven Observability**
  - Events published at every workflow transition point
  - Custom subscribers for external integrations (Sentry, PagerDuty, Slack)
  - OpenTelemetry integration for production observability
  - Complete event catalog for discovery and documentation

### Event Flow Architecture

Throughout the workflow execution, Tasker publishes events that enable comprehensive observability and custom integrations:

- **Task Events**: `task.started`, `task.completed`, `task.failed`
- **Step Events**: `step.started`, `step.completed`, `step.failed`, `step.retry_requested`
- **Workflow Events**: `workflow.viable_steps_discovered`, `workflow.no_viable_steps`
- **Observability Events**: Performance and monitoring metrics

For complete documentation on the event system and creating custom subscribers, see [EVENT_SYSTEM.md](EVENT_SYSTEM.md).
