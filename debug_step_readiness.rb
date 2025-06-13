# Debug script to understand step readiness issues
# Run with: bundle exec rails runner debug_step_readiness.rb

# Load factories
Dir[Rails.root.join('spec/factories/**/*.rb')].each { |f| require f }
Dir[Rails.root.join('spec/support/**/*.rb')].each { |f| require f }

# Register the DummyTask handler
require_relative 'spec/mocks/dummy_task'
Tasker::HandlerFactory.instance.register(DummyTask::TASK_REGISTRY_NAME, DummyTask)

puts "Creating dummy task..."
task = FactoryBot.create(:dummy_task_workflow, context: { dummy: true })
puts "Task created: #{task.task_id}, status: #{task.status}"
puts "Steps: #{task.workflow_steps.count}"

task.workflow_steps.each do |step|
  puts "  - #{step.name}: #{step.status} (processed: #{step.processed}, attempts: #{step.attempts})"
end

puts "\nStep readiness status:"
readiness_statuses = Tasker::StepReadinessStatus.for_task(task.task_id)
readiness_statuses.each do |status|
  puts "  - #{status.name}: state=#{status.current_state}, ready=#{status.ready_for_execution}, retry_eligible=#{status.retry_eligible}"
end

puts "\nFinding viable steps..."
sequence = Tasker::Types::StepSequence.new(task.workflow_steps.includes(:named_step))
viable_steps = Tasker::Orchestration::ViableStepDiscovery.new.find_viable_steps(task, sequence)
puts "Viable steps: #{viable_steps.count}"
viable_steps.each do |step|
  puts "  - #{step.name}: #{step.status}"
end

if viable_steps.any?
  puts "\nExecuting one iteration..."
  handler = Tasker::HandlerFactory.instance.get(DummyTask::TASK_REGISTRY_NAME)

  # Execute one step
  step_executor = Tasker::Orchestration::StepExecutor.new
  processed_steps = step_executor.execute_steps(task, sequence, viable_steps, handler)

  puts "Processed steps: #{processed_steps.count}"
  processed_steps.each do |step|
    puts "  - #{step.name}: #{step.status} (processed: #{step.processed})"
  end

  # Check task status after processing
  task.reload
  puts "\nTask status after processing: #{task.status}"

  # Check step readiness again
  puts "\nStep readiness after processing:"
  readiness_statuses = Tasker::StepReadinessStatus.for_task(task.task_id)
  readiness_statuses.each do |status|
    puts "  - #{status.name}: state=#{status.current_state}, ready=#{status.ready_for_execution}"
  end
else
  puts "No viable steps found!"
end
