# typed: false
# frozen_string_literal: true

class DummyTask
  include Tasker::TaskHandler

  # these are just for readability, they could just be strings elsewhere
  DUMMY_SYSTEM = 'dummy-system'
  STEP_ONE = 'step-one'
  STEP_TWO = 'step-two'
  STEP_THREE = 'step-three'
  STEP_FOUR = 'step-four'
  STEP_FIVE = 'step-five'
  ANNOTATION_TYPE = 'dummy-annotation'
  TASK_REGISTRY_NAME = 'dummy_task'

  # this is for convenience to read, it could be any class that has a handle method with this signature
  class Handler
    # the handle method is only expected to catch around recoverable errors
    # it is responsible for setting results back on the step
    # anything that raises StandardError or subclass will be caught
    # by the wrapper logic in TaskHandler
    def handle(_task, _sequence, step)
      # task and sequence are passed in
      # in case the task context or the sequence's prior steps
      # may contain data that is necessary for the handling of this step
      step.results = { dummy: true }
    end
  end

  # this is critical - if the handler factory does not register your task handler
  # the Tasker system will not know how to either validate a request
  # or ultimately handle the steps
  register_handler(TASK_REGISTRY_NAME)

  # this makes it easier to define step templates for a handler
  # you could alternatively create an instance method `step_templates`
  # that returns an array of Tasker::StepTemplate's
  # only name and handler_class are required, but others help with
  # visibility and findability
  define_step_templates do |templates|
    templates.define(
      dependent_system: DUMMY_SYSTEM,
      name: STEP_ONE,
      description: 'Independent Step One',
      # these are the defaults, omitted elsewhere for brevity
      default_retryable: true,
      default_retry_limit: 3,
      skippable: false,
      handler_class: DummyTask::Handler
    )
    templates.define(
      dependent_system: DUMMY_SYSTEM,
      name: STEP_TWO,
      description: 'Independent Step Two',
      handler_class: DummyTask::Handler
    )
    templates.define(
      dependent_system: DUMMY_SYSTEM,
      name: STEP_THREE,
      depends_on_step: STEP_TWO,
      description: 'Step Three Dependent on Step Two',
      handler_class: DummyTask::Handler
    )
    templates.define(
      dependent_system: DUMMY_SYSTEM,
      name: STEP_FOUR,
      depends_on_step: STEP_THREE,
      description: 'Step Four Dependent on Step Three',
      handler_class: DummyTask::Handler
    )
  end

  # this should conform to the json-schema gem's expectations for how to validate json
  # used to validate the context of a given TaskRequest whether from the API or otherwise
  def schema
    @schema ||= { type: :object, required: [:dummy], properties: { dummy: { type: 'boolean' } } }
  end

  def update_annotations(task, _sequence, steps)
    annotatable_steps = steps.filter { |step| step.status == Tasker::Constants::WorkflowStepStatuses::COMPLETE }
    annotation_type = Tasker::AnnotationType.find_or_create_by!(name: ANNOTATION_TYPE)
    annotatable_steps.each do |step|
      Tasker::TaskAnnotation.create(
        task: task,
        task_id: task.task_id,
        annotation_type_id: annotation_type.annotation_type_id,
        annotation_type: annotation_type,
        annotation: {
          dummy_annotation: 'something that might be important',
          step_name: step.name
        }
      )
    end
  end
end
