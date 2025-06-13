# Test script to verify backoff logic in SQL function
# Run this in Rails console or with rails runner

require 'factory_bot_rails'
include FactoryBot::Syntax::Methods

puts "=== Testing Backoff Logic in SQL Function ==="

# Create a task with two steps
task = create(:dummy_task_workflow, :for_orchestration, with_dependencies: true)

puts "\n=== Task Information ==="
puts "Task ID: #{task.task_id}"
puts "Number of steps: #{task.workflow_steps.count}"

# Get the two independent steps (step-one and step-two)
step_one = task.workflow_steps.joins(:named_step).find_by(named_step: { name: 'step-one' })
step_two = task.workflow_steps.joins(:named_step).find_by(named_step: { name: 'step-two' })

puts "\n=== Before Backoff ==="
puts "Step One ID: #{step_one.workflow_step_id}"
puts "Step Two ID: #{step_two.workflow_step_id}"

# Test SQL function before backoff
results = ActiveRecord::Base.connection.execute(
  "SELECT * FROM get_step_readiness_status(#{task.task_id})"
)

results.each do |row|
  puts "Step: #{row['name']} - ready_for_execution: #{row['ready_for_execution']}"
end

puts "\n=== Setting Step One to Backoff ==="
# Set step_one to backoff (30 seconds from now)
step_one.update_columns(
  backoff_request_seconds: 30,
  last_attempted_at: Time.current
)

puts "Step One backoff_request_seconds: #{step_one.reload.backoff_request_seconds}"
puts "Step One last_attempted_at: #{step_one.last_attempted_at}"

puts "\n=== After Backoff ==="
# Test SQL function after backoff
results = ActiveRecord::Base.connection.execute(
  "SELECT * FROM get_step_readiness_status(#{task.task_id})"
)

results.each do |row|
  puts "Step: #{row['name']} - ready_for_execution: #{row['ready_for_execution']}, backoff_request_seconds: #{row['backoff_request_seconds']}, last_attempted_at: #{row['last_attempted_at']}"
end

puts "\n=== Expected Result ==="
puts "step-one should have ready_for_execution: false (due to backoff)"
puts "step-two should have ready_for_execution: true (no backoff)"
