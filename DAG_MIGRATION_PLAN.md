# Directed Acyclic Graph Migration Plan

* We have already introduced a new `WorkflowStepEdge` model that will be used to represent the DAG of workflow steps.
* We need to migrate the existing workflow steps to use the new `WorkflowStepEdge` model.

## Backward Compatibility to Start

* The current workflow step model relies on the `depends_on_step_id` column to determine the order of execution.
* We have introduced a DAG data structure for steps
* The first migration will be to back-port the depends_on_step_id as an add_provides_edge call
* Then we will change the following:
  * scopes and queries
  * validations
  * step builder
  * task handler
  * task handler class methods
  * task handler instance methods

## Breaking Change?

* We can probably avoid a breaking change by allowing the `depends_on_step` to be legacy compatible in the step template
* But underneath we will combine to depends_on_steps and add_provides_edge calls

## Stepwise Plan

1. [x] Create a data migration back-porting the `depends_on_step_id` to the `add_provides_edge` call
2. [x] Update all instances of `depends_on_step_id` or `depends_on_step` to consider in terms of children and parents of the edges
3. [x] Update the methodology of finding the next valid steps to be based on the DAG
4. [x] Walk the DAG down multiple parallel paths when they do not have dependencies to a configurable breadth and number of threads
5. [x] Restructure the step template definion to use the concept of `depends_on_steps`

## Next up: Concurrency

* We need to add a new `concurrency_config` to the task handler
* This will be used to determine the number of steps that can be run in parallel
* We will also need to update the step handler to support this
* We will also need to update the task handler to support this

