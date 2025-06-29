# Tasker Project Brief

## Project Overview
Tasker is a Ruby gem that provides a sophisticated workflow orchestration system for managing complex, multi-step tasks with dependencies, retry logic, and state management. It's designed to handle enterprise-level workflow automation with high reliability and observability.

## Core Requirements

### Primary Goals
1. **Reliable Workflow Execution**: Execute complex workflows with multiple steps and dependencies without data loss or corruption
2. **Retry & Recovery**: Intelligent retry mechanisms with exponential backoff for failed steps
3. **State Management**: Robust state machine implementation for both tasks and workflow steps
4. **Performance**: High-performance SQL functions for step readiness and task execution context
5. **Observability**: Comprehensive event system and telemetry for monitoring workflow execution
6. **Testing Infrastructure**: Sophisticated test harness for validating complex workflow scenarios

### Key Features
- **DAG-based Workflow Definition**: Define workflows as directed acyclic graphs with step dependencies
- **Function-based Performance**: PostgreSQL functions for high-performance step readiness calculations
- **Event-driven Architecture**: Publish/subscribe system for workflow lifecycle events
- **Configurable Retry Logic**: Exponential backoff, retry limits, and custom retry strategies
- **Test Orchestration**: Specialized test coordinators for synchronous workflow testing
- **ActiveJob Integration**: Seamless integration with Rails ActiveJob for asynchronous processing

## Success Criteria
1. All workflow tests pass consistently
2. SQL functions correctly identify step readiness and retry eligibility
3. Tasks complete successfully from start to finish
4. Failed steps can be retried according to configured policies
5. Test infrastructure supports complex workflow validation scenarios

## Current Status
- **COMPLETE INFRASTRUCTURE REPAIR ACHIEVED**: **1,692 tests passing (0 failures)**
- **Critical Infrastructure Fixed**: MetricsBackend initialization, database queries, test architecture
- **Operational Optimization Complete**: TTL values optimized for real-time monitoring
- **Test Architecture Modernized**: All CacheStrategy tests updated to Rails.cache-only architecture
- **100% Test Reliability**: Configuration-aware cache keys prevent cross-test contamination
- **Enterprise-Ready**: Complete distributed coordination with intelligent cache strategy

## Project Scope
This is a mature Ruby gem project focused on workflow orchestration that has achieved **enterprise-scale reliability**. The core functionality is fully implemented with **100% test success**, and current capabilities include:
- **Complete Infrastructure Stability**: Zero failing tests with comprehensive error handling
- **Intelligent Cache Strategy**: Distributed coordination with adaptive TTL calculation
- **Operational Excellence**: Real-time monitoring with optimized cache TTL values
- **Test Architecture Excellence**: Modern test patterns with proper isolation
