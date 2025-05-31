# Debug script to understand step state during creation
puts "=== Step Creation Debug Script ==="

# Load Rails environment
require_relative 'spec/dummy/config/environment'
require_relative 'spec/mocks/dummy_task'

# Register the dummy task handler
Tasker::HandlerFactory.instance.register(DummyTask::TASK_REGISTRY_NAME, DummyTask)

# Clean up existing dummy tasks
Tasker::Task.joins(:named_task)
            .where(named_task: { name: DummyTask::TASK_REGISTRY_NAME })
            .destroy_all

puts "\n=== Creating TaskRequest ==="
task_request = Tasker::Types::TaskRequest.new(
  name: DummyTask::TASK_REGISTRY_NAME,
  initiator: 'debug@test.com',
  reason: 'debugging step creation',
  source_system: 'debug-system',
  context: { dummy: true },
  tags: %w[debug],
  bypass_steps: []
)

puts "\n=== Creating Task ==="
task = Tasker::Task.create_with_defaults!(task_request)
puts "Task created with ID: #{task.task_id}"
puts "Task status (direct): #{task.read_attribute(:status)}"
puts "Task status (method): #{task.status}"
puts "Task state machine current state: #{task.state_machine.current_state}"

puts "\n=== Before step creation ==="
puts "Number of workflow steps: #{task.workflow_steps.count}"

puts "\n=== Getting step templates ==="
task_handler = Tasker::HandlerFactory.instance.get(DummyTask::TASK_REGISTRY_NAME)
step_templates = task_handler.step_templates
puts "Step templates count: #{step_templates.size}"
step_templates.each { |t| puts "  - #{t.name}" }

puts "\n=== Creating steps via get_steps_for_task ==="
steps = Tasker::WorkflowStep.get_steps_for_task(task, step_templates)
puts "Steps created: #{steps.size}"

puts "\n=== Checking step states after creation ==="
steps.each_with_index do |step, index|
  puts "Step #{index + 1}: #{step.name}"
  puts "  - Persisted: #{step.persisted?}"
  puts "  - Status (direct): #{step.read_attribute(:status)}"
  puts "  - Status (method): #{step.status}"
  puts "  - State machine current state: #{step.state_machine.current_state}"
  puts "  - Transitions count: #{step.workflow_step_transitions.count}"
  if step.workflow_step_transitions.any?
    step.workflow_step_transitions.each do |t|
      puts "    - Transition: #{t.from_state} -> #{t.to_state} (most_recent: #{t.most_recent})"
    end
  end
  puts "  - Processed: #{step.processed}"
  puts "  - In process: #{step.in_process}"
  puts ""
end

puts "\n=== Establishing dependencies ==="
task_handler.establish_step_dependencies_and_defaults(task, steps)

puts "\n=== Final step states after establish_step_dependencies_and_defaults ==="
task.reload
task.workflow_steps.each_with_index do |step, index|
  puts "Step #{index + 1}: #{step.name}"
  puts "  - Status (method): #{step.status}"
  puts "  - State machine current state: #{step.state_machine.current_state}"
  puts "  - Transitions count: #{step.workflow_step_transitions.count}"
  puts "  - Processed: #{step.processed}"
  puts ""
end

puts "=== Debug script complete ==="
