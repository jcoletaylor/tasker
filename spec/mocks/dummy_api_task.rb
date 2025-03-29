# typed: false
# frozen_string_literal: true

class DummyApiTask
  include Tasker::TaskHandler

  # these are just for readability, they could just be strings elsewhere
  DUMMY_SYSTEM = 'dummy-system'
  STEP_ONE = 'step-one'
  ANNOTATION_TYPE = 'dummy-annotation'
  TASK_REGISTRY_NAME = 'dummy_api_task'

  # this is for convenience to read, it could be any class that has a handle method with this signature
  class Handler < Tasker::StepHandler::Api
    # the call method is expected to raise around recoverable errors
    # the handle method still sets results automatically, but call returns the results
    # and is responsible for using the connection object to make the API call
    def call(_task, _sequence, step)
      connection.get('/', { step_name: step.name })
    end
  end

  # register the task handler with the handler factory
  register_handler(TASK_REGISTRY_NAME)

  # define steps for the step handlers
  # only name and handler_class are required, but others help with visibility and findability
  define_step_templates do |templates|
    templates.define(
      dependent_system: DUMMY_SYSTEM,
      name: STEP_ONE,
      description: 'Independent Step One',
      # these are the defaults, omitted elsewhere for brevity
      default_retryable: true,
      default_retry_limit: 3,
      skippable: false,
      handler_class: DummyApiTask::Handler,
      handler_config: Tasker::StepHandler::Api::Config.new(
        url: 'https://api.dummy-system.com/step-one',
        params: { dummy: true }
      )
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
