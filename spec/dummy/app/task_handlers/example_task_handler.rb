# typed: strict
# frozen_string_literal: true

# Example task handler for the Tasker gem
# This demonstrates how to create a task handler with proper type annotations,
# step templates, and registration with the HandlerFactory
class ExampleTaskHandler
  extend T::Sig
  include Tasker::TaskHandler

  # Register this handler with the HandlerFactory
  register_handler :example_task

  # Define the context schema for validation
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def schema
    {
      type: 'object',
      required: ['input_data'],
      properties: {
        input_data: {
          type: 'string',
          description: 'Input data for the task'
        },
        optional_field: {
          type: 'string',
          description: 'An optional field'
        }
      }
    }
  end

  # Define the step templates for this task
  define_step_templates do |definer|
    definer.define(
      name: :first_step,
      handler_class: 'FirstStepHandler',
      description: 'First step of the example task',
      dependent_system: 'ExampleSystem',
      default_retryable: true,
      default_retry_limit: 3
    )

    definer.define(
      name: :second_step,
      handler_class: 'SecondStepHandler',
      description: 'Second step of the example task',
      dependent_system: 'ExampleSystem',
      depends_on_step: :first_step,
      default_retryable: true,
      default_retry_limit: 2
    )
  end

  # Override to establish dependencies between steps
  sig { override.params(task: Tasker::Task, steps: T::Array[Tasker::WorkflowStep]).void }
  def establish_step_dependencies_and_defaults(task, steps)
    # This method can be used to set up additional dependencies or defaults
    # based on the task's context
  end

  # Override to update annotations
  sig do
    override.params(task: Tasker::Task, sequence: Tasker::StepSequence, steps: T::Array[Tasker::WorkflowStep]).void
  end
  def update_annotations(task, sequence, steps)
    # This method can be used to add annotations to the task based on step results
  end
end

# Define the step handler classes
class FirstStepHandler
  extend T::Sig

  sig { params(task: Tasker::Task, sequence: Tasker::StepSequence, step: Tasker::WorkflowStep).void }
  def handle(_task, _sequence, step)
    # Example implementation that processes the first step
    # In a real implementation, this would do something with task.context
    step.results = { status: 'completed', message: 'First step completed successfully' }
  end
end

class SecondStepHandler
  extend T::Sig

  sig { params(task: Tasker::Task, sequence: Tasker::StepSequence, step: Tasker::WorkflowStep).void }
  def handle(_task, sequence, step)
    # Example implementation that processes the second step
    # This would typically use results from the first step
    first_step = sequence.steps.find { |s| s.name == 'first_step' }
    step.results = {
      status: 'completed',
      message: 'Second step completed successfully',
      first_step_result: first_step&.results
    }
  end
end
