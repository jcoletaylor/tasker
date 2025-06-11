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
      pattern_distribution do
        {
          linear: 0.3,
          diamond: 0.25,
          parallel_merge: 0.2,
          tree: 0.15,
          mixed: 0.1
        }
      end
      failure_percentage { 0.15 }
      completion_percentage { 0.6 }
    end

    initialize_with do
      tasks = []

      # Calculate counts for each pattern based on task_count
      pattern_counts = pattern_distribution.transform_values { |ratio| (task_count * ratio).round }

      # Adjust for rounding differences
      total_assigned = pattern_counts.values.sum
      if total_assigned < task_count
        pattern_counts[:linear] += task_count - total_assigned
      elsif total_assigned > task_count
        pattern_counts[:linear] -= total_assigned - task_count
      end

      total_created = 0
      pattern_counts.each do |pattern, count|
        count.times do |i|
          # Use the step template-based factories instead of the old complex_workflow factory
          factory_name = case pattern
                         when :linear
                           :linear_workflow_task
                         when :diamond
                           :diamond_workflow_task
                         when :parallel_merge
                           :parallel_merge_workflow_task
                         when :tree
                           :tree_workflow_task
                         when :mixed
                           :mixed_workflow_task
                         else
                           :linear_workflow_task # fallback
                         end

          task = create(factory_name,
                        context: {
                          workflow_type: pattern.to_s,
                          batch_id: "dataset_#{Time.current.to_i}",
                          task_index: total_created + i,
                          pattern: pattern,
                          created_at: Time.current.to_f
                        },
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
  # Use the EXACT handler name - many tasks should share the same NamedTask
  # This is critical for proper handler lookup in the HandlerFactory

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

    # Set completed steps first (to satisfy dependencies for other steps)
    evaluator.completed_step_names.each do |step_name|
      step = task.workflow_steps.joins(:named_step)
                 .where(tasker_named_steps: { name: step_name }).first
      next unless step

      # Complete dependencies first to ensure state machine guards pass
      complete_step_dependencies(step)

      # Use safe state machine transitions
      begin
        current_state = step.state_machine.current_state
        current_state = Tasker::Constants::WorkflowStepStatuses::PENDING if current_state.blank?

        # Only transition if not already complete
        completion_states = [
          Tasker::Constants::WorkflowStepStatuses::COMPLETE,
          Tasker::Constants::WorkflowStepStatuses::RESOLVED_MANUALLY
        ]

        unless completion_states.include?(current_state)
          # Transition to in_progress first if not already there
          unless current_state == Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS
            step.state_machine.transition_to!(:in_progress)
          end

          # Then transition to complete
          step.state_machine.transition_to!(:complete)
          step.update_columns(processed: true, processed_at: Time.current)
        end
      rescue StandardError => e
        Rails.logger.warn "Could not transition step #{step_name} to complete state: #{e.message}"
      end
    end

    # Set failed steps after completing dependencies
    evaluator.failure_step_names.each do |step_name|
      step = task.workflow_steps.joins(:named_step)
                 .where(tasker_named_steps: { name: step_name }).first
      next unless step

      # Complete dependencies first to ensure state machine guards pass
      complete_step_dependencies(step)

      # Use safe state machine transitions for error state
      begin
        current_state = step.state_machine.current_state
        current_state = Tasker::Constants::WorkflowStepStatuses::PENDING if current_state.blank?

        # Only transition if not already in error or complete
        unless [
          Tasker::Constants::WorkflowStepStatuses::ERROR,
          Tasker::Constants::WorkflowStepStatuses::COMPLETE,
          Tasker::Constants::WorkflowStepStatuses::RESOLVED_MANUALLY
        ].include?(current_state)
          # Transition to in_progress first if not already there
          unless current_state == Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS
            step.state_machine.transition_to!(:in_progress)
          end

          # Then transition to error
          step.state_machine.transition_to!(:error)
          step.update_columns(processed: false, results: { error: 'Factory-generated error' })
        end
      rescue StandardError => e
        Rails.logger.warn "Could not transition step #{step_name} to error state: #{e.message}"
      end
    end
  end

  # Complete any dependencies for a step to ensure state machine guards pass
  def self.complete_step_dependencies(step)
    return unless step.respond_to?(:parents)

    parents = step.parents
    return if parents.blank?

    parents.each do |parent|
      # Check if parent is already complete
      completion_states = [
        Tasker::Constants::WorkflowStepStatuses::COMPLETE,
        Tasker::Constants::WorkflowStepStatuses::RESOLVED_MANUALLY
      ]
      current_state = parent.state_machine.current_state
      parent_status = current_state.presence || Tasker::Constants::WorkflowStepStatuses::PENDING

      # If parent isn't complete, complete it recursively
      unless completion_states.include?(parent_status)
        Rails.logger.debug do
          "Factory Helper: Completing parent step #{parent.workflow_step_id} to satisfy dependency for step #{step.workflow_step_id}"
        end

        # Recursively complete parent's dependencies first
        complete_step_dependencies(parent)

        # Then complete the parent
        begin
          unless parent_status == Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS
            parent.state_machine.transition_to!(:in_progress)
          end
          parent.state_machine.transition_to!(:complete)
          parent.update_columns(processed: true, processed_at: Time.current)
        rescue StandardError => e
          Rails.logger.warn "Could not complete parent step #{parent.workflow_step_id}: #{e.message}"
        end
      end
    end
  end
end
