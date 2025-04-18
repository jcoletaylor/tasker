# Tasker TODO List

## High Priority (High Impact, Reasonable Effort)

1. **Parallel Step Execution**
   - [x] Implement concurrent execution for independent steps
   - [x] Add configuration options to control parallelism levels
   - [x] Modify step dependency resolution to handle parallel execution paths

2. **Create Rich Examples with API Integrations**
   - [x] Develop examples integrating with common RESTful services
   - [x] Build examples demonstrating error handling and resilience techniques

3. **Enhanced Backoff Strategies**
   - [x] Implement exponential backoff with jitter

4. **Allow for Configurable Task Identity**
   - [x] Make task identity hash optional with GUID fallback
   - [x] Implement strategy pattern for custom identity hash implementations
   - [x] Add configurability for identity uniqueness time windows

5. **Backend Queue Flexibility**
   - [x] Use ActiveJob as an abstraction layer for queue implementations

## Medium Priority (Significant Value, Moderate Effort)

1. **Optional OpenTelemetry Metrics Collection**
    - [x] Integrate with common metrics libraries
    - [x] Add observable lifecycle events for task execution

2. **Workflow Diagrams for Task Definitions**
   - [ ] Generate visual representation of task definitions
   - [ ] Add tooling to visualize task execution paths
   - [ ] Create documentation showing workflow examples with diagrams

3. **Task Handler Versioning**
    - [ ] Add support for versioned task handlers
    - [ ] Implement migration paths between handler versions
    - [ ] Allow multiple versions of handlers to run concurrently
