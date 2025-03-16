# Tasker Features Documentation

## Overview
Tasker is a Rails engine that manages multi-step workflow tasks. This document outlines the current features and structure as of March 2025, before the upgrade to Ruby 3.4 and Rails 8.

## Current Versions
- Ruby: 2.7.3
- Rails: 6.1.4

## Core Components

### Data Models

#### Task ([source](app/models/tasker/task.rb))
- Core entity representing a workflow
- Key features:
    * Status tracking (complete, pending)
    * Metadata: initiator, source_system
    * JSON context and tags support
    * Duplicate prevention via identity_hash
    * Related to workflow steps and annotations

#### WorkflowStep ([source](app/models/tasker/workflow_step.rb))
- Represents individual steps within a task
- Features:
    * Step dependencies
    * Retry mechanism with configurable limits
    * Execution status tracking
    * Attempt counting
    * Optional skip functionality
    * Backoff timing support

#### NamedTask ([source](app/models/tasker/named_task.rb))
- Template/definition for tasks
- Provides reusable task definitions
- Maintains unique task names

#### NamedStep ([source](app/models/tasker/named_step.rb))
- Template/definition for workflow steps
- Associates steps with dependent systems
- Ensures uniqueness within system scope

### API Interfaces

#### REST API
Tasks Controller ([source](app/controllers/tasker/tasks_controller.rb))
- Endpoints:
    * GET /tasks - List tasks with pagination
    * GET /tasks/:id - Show task details
    * POST /tasks - Create new task
    * PATCH/PUT /tasks/:id - Update task
    * DELETE /tasks/:id - Cancel task

#### GraphQL API
Schema ([source](app/graphql/tasker/tasker_rails_schema.rb))
- Query Features:
    * Task queries ([source](app/graphql/tasker/types/query_type.rb))
    * Status-based filtering
    * Annotation-based queries
    * Complex nested queries

### Key Features

#### Step Dependencies
- Steps can depend on other steps
- Dependency validation
- Sequential execution support
- Results and inputs validation between steps

#### Retry Mechanism
- Configurable retry limits
- Backoff timing support
- Failure handling
- Progress tracking

#### Task Identity
- Duplicate detection within time windows
- Identity based on:
    * Task name
    * Initiator
    * Source system
    * Context
    * Reason
    * Bypass steps
    * Request timing

#### Type System
- Sorbet integration
- Runtime type checking
- Strict typing in critical paths

### Database Features
- PostgreSQL specific:
    * JSONB for context and tags
    * GIN indexes for JSON fields
- Complex foreign key relationships
- Unique constraints
- Performance optimized indexes

## Upgrade Notes
This documentation serves as a baseline for the planned upgrade to:
- Ruby 3.4 or better
- Rails 8.0

The upgrade process will need to maintain all current functionality while modernizing the codebase.

