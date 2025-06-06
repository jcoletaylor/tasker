# frozen_string_literal: true

# Simple test handler for orchestration testing
# This provides a minimal but realistic handler that integrates with the
# existing plugin patterns while being simple enough for testing.
class MinimalTestHandler
  include Tasker::TaskHandler::InstanceMethods

  def step_templates
    [
      Tasker::StepTemplate.new(
        name: 'test_step',
        description: 'Test step for orchestration',
        class_name: 'MinimalTestStepHandler',
        dependent_system: 'test_system',
        all_dependencies: []
      )
    ]
  end

  def get_step_handler(_step)
    MinimalTestStepHandler.new
  end
end

# Simple test step handler that actually does work
class MinimalTestStepHandler
  def handle(task, _sequence, step)
    # Simple test logic - just mark as processed with realistic data
    step.results = {
      test: true,
      handled_at: Time.current,
      handler_class: self.class.name,
      task_id: task.task_id,
      step_name: step.name
    }
    step.save!
  end
end
