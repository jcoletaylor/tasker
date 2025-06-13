#!/usr/bin/env ruby

# Debug script to investigate workflow execution issues
ENV['RAILS_ENV'] = 'test'
require_relative 'spec/dummy/config/environment'
require 'factory_bot_rails'

# Configure FactoryBot paths for the engine (same as rails_helper)
engine_factory_path = File.expand_path('spec/factories', __dir__)
unless FactoryBot.definition_file_paths.include?(engine_factory_path)
  FactoryBot.definition_file_paths << engine_factory_path
end

# Reload to pick up all factories
FactoryBot.reload

puts "=== Debugging Workflow Execution Issue ==="

# Create a simple task to debug
task = FactoryBot.create(:task, :with_steps, name: 'dummy_task')
puts "Created task: #{task.task_id} with status: #{task.status}"

# Check if the task has workflow steps
steps = task.workflow_steps
puts "Task has #{steps.count} workflow steps:"
steps.each do |step|
  puts "  - Step #{step.workflow_step_id}: #{step.name}, processed: #{step.processed}, in_process: #{step.in_process}"
  puts "    State: #{step.status}"
end

# Check what the SQL function returns
puts "\n=== SQL Function Results ==="
readiness_results = Tasker::StepReadinessStatus.for_task(task.task_id)
puts "SQL function returned #{readiness_results.count} results:"
readiness_results.each do |result|
  puts "  - Step #{result.workflow_step_id}: #{result.name}"
  puts "    Current state: #{result.current_state}"
  puts "    Dependencies satisfied: #{result.dependencies_satisfied}"
  puts "    Retry eligible: #{result.retry_eligible}"
  puts "    Ready for execution: #{result.ready_for_execution}"
  puts "    Total parents: #{result.total_parents}, Completed parents: #{result.completed_parents}"
end

# Check task execution context
puts "\n=== Task Execution Context ==="
context = Tasker::TaskExecutionContext.find(task.task_id)
if context
  puts "Execution status: #{context.execution_status}"
  puts "Ready steps: #{context.ready_steps}"
  puts "Total steps: #{context.total_steps}"
  puts "Pending steps: #{context.pending_steps}"
  puts "In progress steps: #{context.in_progress_steps}"
  puts "Completed steps: #{context.completed_steps}"
  puts "Failed steps: #{context.failed_steps}"
else
  puts "No task execution context found"
end

# Check viable steps using the WorkflowStep method
puts "\n=== Viable Steps Check ==="
task_handler = Tasker::HandlerFactory.instance.get(task.name)
sequence = task_handler.get_sequence(task)
viable_steps = Tasker::WorkflowStep.get_viable_steps(task, sequence)
puts "WorkflowStep.get_viable_steps returned #{viable_steps.count} viable steps:"
viable_steps.each do |step|
  puts "  - Step #{step.workflow_step_id}: #{step.name}"
end

puts "\n=== Debug Complete ==="
