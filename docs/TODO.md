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
   - [ ] Make task identity hash optional with GUID fallback
   - [ ] Implement strategy pattern for custom identity hash implementations
   - [ ] Add configurability for identity uniqueness time windows

5. **Backend Queue Flexibility**
   - [x] Use ActiveJob as an abstraction layer for queue implementations

## Medium Priority (Significant Value, Moderate Effort)

1. **Workflow Diagrams for Task Definitions**
   - [ ] Generate visual representation of task definitions
   - [ ] Add tooling to visualize task execution paths
   - [ ] Create documentation showing workflow examples with diagrams

2. **Task Handler Versioning**
    - [ ] Add support for versioned task handlers
    - [ ] Implement migration paths between handler versions
    - [ ] Allow multiple versions of handlers to run concurrently

3. **Optional OpenTelemetry Metrics Collection**
    - [ ] Integrate with common metrics libraries
    - [ ] Collect performance and operational metrics
    - [ ] Add configurable metric exporters

## Future Enhancements (Valuable, Higher Effort)

1. **Scheduled Tasks**
    - [ ] Add support for future task scheduling
    - [ ] Implement efficient polling for scheduled tasks
    - [ ] Add timezone support for scheduling

2.  **Task Cleanup Policies**
    - [ ] Add configurable retention policies for completed tasks
    - [ ] Implement efficient archiving strategies
    - [ ] Create tools for data migration/archiving

3.  **Retry Callback Hooks**
    - [ ] Add extensible hook points for retry events
    - [ ] Implement customizable retry policies
    - [ ] Add support for external retry decision makers

4.  **Rate Limiting Support**
    - [ ] Add built-in rate limiting for integrations
    - [ ] Implement token bucket algorithm for smooth rate control
    - [ ] Add per-integration rate limit configuration
