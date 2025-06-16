# frozen_string_literal: true

# Debug script to examine SQL function behavior
# Run this in Rails console

# Load FactoryBot and include it
require 'factory_bot_rails'
include FactoryBot::Syntax::Methods

puts '=== SQL Function Debug ==='

# Create a dummy task using the same factory as the failing test
task = create(:dummy_task_workflow, :for_orchestration, with_dependencies: true)

puts "\n=== Task Information ==="
puts "Task ID: #{task.task_id}"
puts "Task Status: #{task.status}"
puts "Number of steps: #{task.workflow_steps.count}"

puts "\n=== Step Information ==="
task.workflow_steps.includes(:named_step, :workflow_step_transitions).find_each do |step|
  puts "Step: #{step.named_step.name} (ID: #{step.workflow_step_id})"
  puts "  - processed: #{step.processed}"
  puts "  - in_process: #{step.in_process}"
  puts "  - attempts: #{step.attempts}"
  puts "  - retry_limit: #{step.retry_limit}"
  puts "  - retryable: #{step.retryable}"
  puts "  - transitions count: #{step.workflow_step_transitions.count}"

  if step.workflow_step_transitions.any?
    latest = step.workflow_step_transitions.order(:sort_key).last
    puts "  - latest transition: #{latest.to_state} (most_recent: #{latest.most_recent})"
  else
    puts '  - NO TRANSITIONS'
  end
  puts
end

puts "\n=== Dependencies ==="
task.workflow_steps.includes(:named_step).find_each do |step|
  parents = step.parents
  puts "Step: #{step.named_step.name}"
  puts "  - Parents: #{parents.map { |p| p.named_step.name }.join(', ')}"
  puts "  - Parent count: #{parents.count}"
  puts
end

puts "\n=== SQL Function Results ==="
begin
  # Test the SQL function directly
  results = ActiveRecord::Base.connection.execute(
    "SELECT * FROM get_step_readiness_status(#{task.task_id})"
  )

  results.each do |row|
    puts "Step: #{row['name']} (ID: #{row['workflow_step_id']})"
    puts "  - current_state: #{row['current_state']}"
    puts "  - dependencies_satisfied: #{row['dependencies_satisfied']}"
    puts "  - retry_eligible: #{row['retry_eligible']}"
    puts "  - ready_for_execution: #{row['ready_for_execution']}"
    puts "  - total_parents: #{row['total_parents']}"
    puts "  - completed_parents: #{row['completed_parents']}"
    puts "  - attempts: #{row['attempts']}"
    puts
  end
rescue StandardError => e
  puts "ERROR calling SQL function: #{e.message}"
  puts e.backtrace.first(5)
end

puts "\n=== Ruby Model Results ==="
begin
  # Test the Ruby model approach
  step_readiness = Tasker::StepReadinessStatus.for_task(task.task_id)

  step_readiness.each do |status|
    puts "Step: #{status.name} (ID: #{status.workflow_step_id})"
    puts "  - current_state: #{status.current_state}"
    puts "  - dependencies_satisfied: #{status.dependencies_satisfied}"
    puts "  - retry_eligible: #{status.retry_eligible}"
    puts "  - ready_for_execution: #{status.ready_for_execution}"
    puts "  - total_parents: #{status.total_parents}"
    puts "  - completed_parents: #{status.completed_parents}"
    puts
  end
rescue StandardError => e
  puts "ERROR with Ruby model: #{e.message}"
  puts e.backtrace.first(5)
end

puts "\n=== Task Finalizer Test ==="
begin
  # Test what TaskFinalizer sees
  Tasker::Orchestration::TaskFinalizer.new

  # Get task execution context
  context = Tasker::TaskExecutionContext.for_task(task.task_id).first
  if context
    puts 'Task Execution Context:'
    puts "  - ready_steps: #{context.ready_steps}"
    puts "  - in_progress_steps: #{context.in_progress_steps}"
    puts "  - completed_steps: #{context.completed_steps}"
    puts "  - failed_steps: #{context.failed_steps}"
    puts "  - total_steps: #{context.total_steps}"
  else
    puts 'NO TASK EXECUTION CONTEXT FOUND'
  end
rescue StandardError => e
  puts "ERROR with TaskFinalizer test: #{e.message}"
  puts e.backtrace.first(5)
end
