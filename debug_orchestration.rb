# frozen_string_literal: true

# Debug script to test step state machine guard clauses
# Run with: bundle exec rails runner debug_orchestration.rb

puts '=== TESTING STEP STATE MACHINE GUARD CLAUSES ==='

# Create a test task
task = Tasker::Task.create!(
  named_task: Tasker::NamedTask.find_or_create_by!(name: 'debug_step_test'),
  context: { test: true },
  requested_at: Time.current
)

puts "Created task #{task.task_id} with initial status: #{task.status}"

# Create a dependent system for the named step
dependent_system = Tasker::DependentSystem.find_or_create_by!(name: 'test_system') do |ds|
  ds.description = 'Test system for debugging'
end

# Create a test step
named_step = Tasker::NamedStep.find_or_create_by!(name: 'debug_step') do |ns|
  ns.dependent_system = dependent_system
  ns.description = 'Test step for debugging'
end

step = Tasker::WorkflowStep.create!(
  task: task,
  named_step: named_step,
  workflow_step_id: SecureRandom.uuid
)

puts "Created step #{step.workflow_step_id} with initial status: #{step.status}"
puts "Step state machine current state: #{step.state_machine.current_state}"

# Test 1: Transition step to IN_PROGRESS
puts "\n=== TEST 1: Step transition to IN_PROGRESS ==="
begin
  puts 'Attempting to transition step to IN_PROGRESS...'
  step.state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
  puts "✅ SUCCESS: Step transitioned to #{step.state_machine.current_state}"
rescue StandardError => e
  puts "❌ ERROR: #{e.message}"
end

# Test 2: Try to transition step to IN_PROGRESS again (should be idempotent)
puts "\n=== TEST 2: Idempotent step transition to IN_PROGRESS ==="
begin
  puts 'Attempting to transition step to IN_PROGRESS again...'
  step.state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
  puts "✅ SUCCESS: Idempotent step transition worked, still in #{step.state_machine.current_state}"
rescue StandardError => e
  puts "❌ ERROR: #{e.message}"
end

# Test 3: Transition to ERROR
puts "\n=== TEST 3: Step transition to ERROR ==="
begin
  puts 'Attempting to transition step to ERROR...'
  step.state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::ERROR)
  puts "✅ SUCCESS: Step transitioned to #{step.state_machine.current_state}"
rescue StandardError => e
  puts "❌ ERROR: #{e.message}"
end

# Test 4: Try to transition step to ERROR again (should be idempotent)
puts "\n=== TEST 4: Idempotent step transition to ERROR ==="
begin
  puts 'Attempting to transition step to ERROR again...'
  step.state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::ERROR)
  puts "✅ SUCCESS: Idempotent step transition worked, still in #{step.state_machine.current_state}"
rescue StandardError => e
  puts "❌ ERROR: #{e.message}"
end

# Test 5: Try to transition from ERROR to IN_PROGRESS (should fail)
puts "\n=== TEST 5: Invalid transition from ERROR to IN_PROGRESS ==="
begin
  puts 'Attempting to transition step from ERROR to IN_PROGRESS...'
  step.state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
  puts '❌ UNEXPECTED SUCCESS: This should have failed!'
rescue StandardError => e
  puts "✅ EXPECTED ERROR: #{e.message}"
end

puts "\n=== GUARD CLAUSE DEBUGGING ==="

# Test the guard clause logic directly
puts 'Testing step guard clause for IN_PROGRESS transition:'
current_step_status = step.state_machine.current_state
puts "Current step status: #{current_step_status}"
puts "Target step status: #{Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS}"
puts "Are they equal? #{current_step_status == Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS}"

# Test dependencies
puts "\nTesting step dependencies:"
puts "Step has parents? #{step.respond_to?(:parents) && step.parents.any?}"
if step.respond_to?(:parents)
  puts "Dependencies met? #{Tasker::StateMachine::StepStateMachine.step_dependencies_met?(step)}"
end
