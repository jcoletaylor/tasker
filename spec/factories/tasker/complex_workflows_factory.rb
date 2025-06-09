# frozen_string_literal: true

FactoryBot.define do
  # Complex Workflow Factory using existing DummyTask infrastructure
  # This simply extends the existing dummy task workflow capabilities for testing
  factory :complex_workflow, class: 'Tasker::Task' do
    # Use dummy_task trait which already has proper workflow setup
    named_task factory: %i[named_task dummy_task]
    initiator { 'batch_processor' }
    source_system { 'integration_testing' }
    reason { 'complex_workflow_testing' }
    context { { workflow_type: 'complex', batch_id: rand(1000..9999) } }

    tags { %w[complex testing performance] }

    transient do
      workflow_pattern { :standard } # Use existing DummyTask workflow
      failure_step_names { [] }
      completed_step_names { [] }
      step_count { 4 } # DummyTask has 4 steps by default
      with_dependencies { true }
    end

    after(:create) do |task, evaluator|
      # Use the existing factory workflow helper infrastructure
      require_relative '../../../spec/support/factory_workflow_helpers'
      extend FactoryWorkflowHelpers

      # Register DummyTask handler
      register_task_handler('dummy_task', DummyTask)

      # Set up workflow using existing helper infrastructure
      FactoryWorkflowHelpers::WorkflowSetupService.configure_workflow(task, evaluator)

      # Apply specific step states if requested
      if evaluator.failure_step_names.any? || evaluator.completed_step_names.any?
        ComplexWorkflowFactoryHelpers.apply_step_states(task, evaluator)
      end
    end

    # Traits for different scenarios
    trait :linear_workflow do
      workflow_pattern { :standard }
    end

    trait :diamond_workflow do
      workflow_pattern { :standard }
    end

    trait :parallel_merge_workflow do
      workflow_pattern { :standard }
    end

    trait :tree_workflow do
      workflow_pattern { :standard }
    end

    trait :mixed_dag_workflow do
      workflow_pattern { :standard }
    end

    # Workflows with partial completion
    trait :partially_completed do
      completed_step_names { %w[step_one step_two] }
    end

    # Workflows with failures
    trait :with_failures do
      failure_step_names { %w[step_three] }
    end

    # Performance batch trait
    trait :performance_batch do
      transient do
        batch_size { 25 }
      end

      after(:create) do |task, evaluator|
        # Create additional tasks for batch testing
        (evaluator.batch_size - 1).times do |i|
          create(:complex_workflow,
                 context: task.context.merge(batch_index: i + 1),
                 initiator: task.initiator,
                 source_system: task.source_system,
                 failure_step_names: evaluator.failure_step_names,
                 completed_step_names: evaluator.completed_step_names)
        end
      end
    end
  end

  # Large Scale Workflow Collection Factory
  # Creates dozens of tasks with various patterns for comprehensive testing
  factory :workflow_dataset, class: 'Array' do
    transient do
      task_count { 30 }
      patterns_distribution do
        {
          linear: 8,
          diamond: 8,
          parallel_merge: 6,
          tree: 4,
          mixed: 4
        }
      end
      failure_percentage { 0.15 }
      completion_percentage { 0.6 }
    end

    initialize_with do
      tasks = []
      total_created = 0

      patterns_distribution.each do |pattern, count|
        count.times do |i|
          failure_steps = rand < failure_percentage ? %w[step_three step_four] : []
          completed_steps = rand < completion_percentage ? %w[step_one step_two] : []

          trait_name = :"#{pattern}_workflow"

          task = create(:complex_workflow, trait_name,
                        context: {
                          batch_id: "dataset_#{Time.current.to_i}",
                          task_index: total_created + i,
                          pattern: pattern
                        },
                        failure_step_names: failure_steps,
                        completed_step_names: completed_steps,
                        reason: "large_dataset_testing_#{pattern}")
          tasks << task
        end
        total_created += count
      end

      tasks
    end
  end

  # Complex workflow patterns using step templates with dependencies
  # These create various DAG structures automatically using Tasker's native workflow system
  # Linear workflow - each step depends on the previous one
  factory :linear_workflow_task, class: 'Tasker::Task' do
    context { { workflow_type: 'linear', batch_id: SecureRandom.uuid } }

    before(:create) do |task, _evaluator|
      # Use shared NamedTask - many tasks can reference the same named_task
      # Handle race conditions with retry logic
      task.named_task = find_or_create_named_task('linear_workflow_task', 'Linear workflow with sequential step dependencies')
    end

    after(:create) do |task, _evaluator|
      # Initialize workflow steps from the task handler step templates
      handler = Tasker::HandlerFactory.instance.get(LinearWorkflowTask::TASK_NAME)
      if handler
        # Create workflow steps using the step templates
        Tasker::Orchestration::StepSequenceFactory.create_sequence_for_task!(task, handler)
      end
    end
  end

  # Diamond workflow - convergent/divergent pattern
  factory :diamond_workflow_task, class: 'Tasker::Task' do
    context { { workflow_type: 'diamond', batch_id: SecureRandom.uuid } }

    before(:create) do |task, _evaluator|
      # Use shared NamedTask - many tasks can reference the same named_task
      task.named_task = find_or_create_named_task('diamond_workflow_task', 'Diamond workflow with convergent/divergent pattern')
    end

    after(:create) do |task, _evaluator|
      # Initialize workflow steps from the task handler step templates
      handler = Tasker::HandlerFactory.instance.get(DiamondWorkflowTask::TASK_NAME)
      if handler
        # Create workflow steps using the step templates
        Tasker::Orchestration::StepSequenceFactory.create_sequence_for_task!(task, handler)
      end
    end
  end

  # Parallel merge workflow - multiple independent branches that converge
  factory :parallel_merge_workflow_task, class: 'Tasker::Task' do
    context { { workflow_type: 'parallel_merge', batch_id: SecureRandom.uuid } }

    before(:create) do |task, _evaluator|
      # Use shared NamedTask - many tasks can reference the same named_task
      task.named_task = find_or_create_named_task('parallel_merge_workflow_task', 'Parallel merge workflow with multiple independent branches')
    end

    after(:create) do |task, _evaluator|
      # Initialize workflow steps from the task handler step templates
      handler = Tasker::HandlerFactory.instance.get(ParallelMergeWorkflowTask::TASK_NAME)
      if handler
        # Create workflow steps using the step templates
        Tasker::Orchestration::StepSequenceFactory.create_sequence_for_task!(task, handler)
      end
    end
  end

  # Tree workflow - hierarchical branching structure
  factory :tree_workflow_task, class: 'Tasker::Task' do
    context { { workflow_type: 'tree', batch_id: SecureRandom.uuid } }

    before(:create) do |task, _evaluator|
      # Use shared NamedTask - many tasks can reference the same named_task
      task.named_task = find_or_create_named_task('tree_workflow_task', 'Tree workflow with hierarchical branching structure')
    end

    after(:create) do |task, _evaluator|
      # Initialize workflow steps from the task handler step templates
      handler = Tasker::HandlerFactory.instance.get(TreeWorkflowTask::TASK_NAME)
      if handler
        # Create workflow steps using the step templates
        Tasker::Orchestration::StepSequenceFactory.create_sequence_for_task!(task, handler)
      end
    end
  end

  # Mixed workflow - complex pattern with multiple dependency types
  factory :mixed_workflow_task, class: 'Tasker::Task' do
    context { { workflow_type: 'mixed', batch_id: SecureRandom.uuid } }

    before(:create) do |task, _evaluator|
      # Use shared NamedTask - many tasks can reference the same named_task
      task.named_task = find_or_create_named_task('mixed_workflow_task', 'Mixed workflow with complex dependency patterns')
    end

    after(:create) do |task, _evaluator|
      # Initialize workflow steps from the task handler step templates
      handler = Tasker::HandlerFactory.instance.get(MixedWorkflowTask::TASK_NAME)
      if handler
        # Create workflow steps using the step templates
        Tasker::Orchestration::StepSequenceFactory.create_sequence_for_task!(task, handler)
      end
    end
  end

  # Batch of complex workflows with various patterns
  factory :complex_workflow_batch, class: 'Hash' do
    skip_create

    transient do
      batch_size { 50 }
      pattern_distribution do
        {
          linear: 0.3,
          diamond: 0.25,
          parallel_merge: 0.2,
          tree: 0.15,
          mixed: 0.1
        }
      end
    end

    initialize_with do
      batch_id = SecureRandom.uuid
      tasks = []

      # Calculate counts for each pattern
      pattern_counts = pattern_distribution.transform_values { |ratio| (batch_size * ratio).round }

      # Adjust for rounding differences
      total_assigned = pattern_counts.values.sum
      if total_assigned < batch_size
        pattern_counts[:linear] += batch_size - total_assigned
      elsif total_assigned > batch_size
        pattern_counts[:linear] -= total_assigned - batch_size
      end

      # Create tasks for each pattern
      task_counter = 0
      pattern_counts.each do |pattern, count|
        count.times do
          task_counter += 1
          # Add unique identifier to avoid identity hash collisions
          unique_context = {
            workflow_type: pattern.to_s,
            batch_id: batch_id,
            task_index: task_counter,
            created_at: Time.current.to_f
          }

          task = case pattern
                 when :linear
                   FactoryBot.create(:linear_workflow_task, context: unique_context)
                 when :diamond
                   FactoryBot.create(:diamond_workflow_task, context: unique_context)
                 when :parallel_merge
                   FactoryBot.create(:parallel_merge_workflow_task, context: unique_context)
                 when :tree
                   FactoryBot.create(:tree_workflow_task, context: unique_context)
                 when :mixed
                   FactoryBot.create(:mixed_workflow_task, context: unique_context)
                 end
          tasks << task
        end
      end

      {
        batch_id: batch_id,
        tasks: tasks,
        total_count: tasks.size,
        pattern_counts: pattern_counts
      }
    end
  end
end

# Helper method to safely find or create NamedTask with race condition handling
def find_or_create_named_task(name, description)
  retries = 0
  begin
    Tasker::NamedTask.find_or_create_by!(name: name) do |named_task|
      named_task.description = description
    end
  rescue ActiveRecord::RecordNotUnique
    retries += 1
    if retries <= 3
      # Brief backoff to handle race conditions
      sleep(0.01 * retries)
      retry
    else
      # If still failing after retries, just find the existing one
      Tasker::NamedTask.find_by!(name: name)
    end
  end
end

# Helper method for applying step states
module ComplexWorkflowFactoryHelpers
  def self.apply_step_states(task, evaluator)
    # Allow some time for the steps to be created
    task.reload

    # Set failed steps
    evaluator.failure_step_names.each do |step_name|
      step = task.workflow_steps.joins(:named_step)
                 .where(tasker_named_steps: { name: step_name }).first
      next unless step

      # Use Tasker's state machine for proper transitions
      begin
        step.state_machine.transition_to!(:in_progress) if step.state_machine.can_transition_to?(:in_progress)
        step.state_machine.transition_to!(:error) if step.state_machine.can_transition_to?(:error)
      rescue StandardError => e
        Rails.logger.warn "Could not transition step #{step_name} to error state: #{e.message}"
      end
    end

    # Set completed steps
    evaluator.completed_step_names.each do |step_name|
      step = task.workflow_steps.joins(:named_step)
                 .where(tasker_named_steps: { name: step_name }).first
      next unless step

      # Use Tasker's state machine for proper transitions
      begin
        step.state_machine.transition_to!(:in_progress) if step.state_machine.can_transition_to?(:in_progress)
        step.state_machine.transition_to!(:complete) if step.state_machine.can_transition_to?(:complete)
      rescue StandardError => e
        Rails.logger.warn "Could not transition step #{step_name} to complete state: #{e.message}"
      end
    end
  end
end
