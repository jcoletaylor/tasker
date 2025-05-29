# frozen_string_literal: true

FactoryBot.define do
  # Complete API Integration Workflow Factory
  # This mirrors the setup from integration_example_spec.rb
  factory :api_integration_workflow, class: 'Tasker::Task' do
    named_task factory: %i[named_task api_integration]
    initiator { 'api_client' }
    source_system { 'ecommerce_api' }
    reason { 'process_cart_checkout' }

    transient do
      with_dependencies { true }
      step_states { :pending } # Can be :pending, :complete, :in_progress, :error
    end

    after(:create) do |task, evaluator|
      if evaluator.with_dependencies
        # Create dependent systems
        api_system = create(:dependent_system, :api_system)
        db_system = create(:dependent_system, :database_system)
        notification_system = create(:dependent_system, :notification_system)

        # Create named steps
        fetch_cart_step = create(:named_step, :fetch_cart, dependent_system: api_system)
        fetch_products_step = create(:named_step, :fetch_products, dependent_system: api_system)
        validate_products_step = create(:named_step, :validate_products, dependent_system: db_system)
        create_order_step = create(:named_step, :create_order, dependent_system: db_system)
        publish_event_step = create(:named_step, :publish_event, dependent_system: notification_system)

        # Create workflow steps with specified state
        step1 = create(:workflow_step, evaluator.step_states,
                       task: task,
                       named_step: fetch_cart_step,
                       inputs: { cart_id: task.context[:cart_id] })

        step2 = create(:workflow_step, evaluator.step_states,
                       task: task,
                       named_step: fetch_products_step,
                       inputs: {})

        step3 = create(:workflow_step, evaluator.step_states,
                       task: task,
                       named_step: validate_products_step,
                       inputs: { cart: {}, products: [] })

        step4 = create(:workflow_step, evaluator.step_states,
                       task: task,
                       named_step: create_order_step,
                       inputs: { cart: {}, validated_products: [] })

        step5 = create(:workflow_step, evaluator.step_states,
                       task: task,
                       named_step: publish_event_step,
                       inputs: { order_id: nil })

        # Create step dependencies
        create(:workflow_step_edge, from_step: step1, to_step: step3, name: 'provides')
        create(:workflow_step_edge, from_step: step2, to_step: step3, name: 'provides')
        create(:workflow_step_edge, from_step: step3, to_step: step4, name: 'provides')
        create(:workflow_step_edge, from_step: step4, to_step: step5, name: 'provides')
      end
    end

    trait :completed_workflow do
      step_states { :complete }
      complete { true }
    end

    trait :in_progress_workflow do
      step_states { :in_progress }
    end

    trait :failed_workflow do
      step_states { :error }
    end
  end

  # Simple Linear Workflow Factory
  factory :simple_linear_workflow, class: 'Tasker::Task' do
    named_task factory: %i[named_task simple_workflow]
    initiator { 'test_system' }
    source_system { 'test' }
    reason { 'testing' }

    transient do
      step_count { 3 }
      step_states { :pending }
    end

    after(:create) do |task, evaluator|
      system = create(:dependent_system, name: 'test_system')

      steps = []
      (1..evaluator.step_count).each do |i|
        named_step = create(:named_step, name: "step_#{i}", dependent_system: system)
        step = create(:workflow_step, evaluator.step_states, task: task, named_step: named_step)
        steps << step

        # Create linear dependencies (each step depends on the previous one)
        create(:workflow_step_edge, from_step: steps[i - 2], to_step: step, name: 'provides') if i > 1
      end
    end

    trait :completed_linear do
      step_states { :complete }
      complete { true }
    end
  end

  # Parallel Processing Workflow Factory
  factory :parallel_workflow, class: 'Tasker::Task' do
    named_task factory: %i[named_task data_processing]
    initiator { 'batch_processor' }
    source_system { 'data_pipeline' }
    reason { 'parallel_processing' }

    transient do
      parallel_count { 3 }
      step_states { :pending }
    end

    after(:create) do |task, evaluator|
      system = create(:dependent_system, :database_system)

      # Create initial step
      init_step_named = create(:named_step, name: 'initialize_batch', dependent_system: system)
      init_step = create(:workflow_step, evaluator.step_states, task: task, named_step: init_step_named)

      # Create parallel processing steps
      parallel_steps = []
      (1..evaluator.parallel_count).each do |i|
        named_step = create(:named_step, name: "process_chunk_#{i}", dependent_system: system)
        step = create(:workflow_step, evaluator.step_states, task: task, named_step: named_step)
        parallel_steps << step

        # Each parallel step depends on the init step
        create(:workflow_step_edge, from_step: init_step, to_step: step, name: 'provides')
      end

      # Create final aggregation step
      final_step_named = create(:named_step, name: 'aggregate_results', dependent_system: system)
      final_step = create(:workflow_step, evaluator.step_states, task: task, named_step: final_step_named)

      # Final step depends on all parallel steps
      parallel_steps.each do |parallel_step|
        create(:workflow_step_edge, from_step: parallel_step, to_step: final_step, name: 'provides')
      end
    end
  end

  # Task with State Machine Transitions (simplified to avoid constraint violations)
  factory :task_with_transitions, class: 'Tasker::Task' do
    named_task

    transient do
      transition_sequence { :complete } # :complete, :error, :retry, :cancel
    end

    # Create the full transition sequence to reach the expected final state
    after(:create) do |task, evaluator|
      # Create initial transition to pending (not most recent)
      create(:task_transition, :initial_transition, task: task, most_recent: false)

      # Create transition to in_progress (not most recent)
      create(:task_transition, :start_transition, task: task, most_recent: false)

      # Create final transition based on the sequence (this is most recent)
      case evaluator.transition_sequence
      when :complete
        create(:task_transition, :complete_transition, task: task, most_recent: true)
      when :error
        create(:task_transition, :error_transition, task: task, most_recent: true)
      when :cancel
        create(:task_transition, :cancel_transition, task: task, most_recent: true)
      else
        # Default to complete
        create(:task_transition, :complete_transition, task: task, most_recent: true)
      end
    end

    trait :completed_with_transitions do
      complete { true }
      transition_sequence { :complete }
    end

    trait :failed_with_transitions do
      transition_sequence { :error }
    end

    trait :retried_with_transitions do
      complete { true }
      transition_sequence { :complete }
    end
  end

  # Workflow Step with Transitions (simplified to avoid constraint violations)
  factory :step_with_transitions, class: 'Tasker::WorkflowStep' do
    task
    named_step

    transient do
      transition_sequence { :success } # :success, :failure, :retry_success, :multiple_retries
    end

    # Create the full transition sequence to reach the expected final state
    after(:create) do |step, evaluator|
      # Create initial transition to pending (not most recent)
      create(:workflow_step_transition, :initial_transition, workflow_step: step, most_recent: false)

      # Create transition to in_progress (not most recent)
      create(:workflow_step_transition, :start_execution, workflow_step: step, most_recent: false)

      # Create final transition based on the sequence (this is most recent)
      case evaluator.transition_sequence
      when :success
        create(:workflow_step_transition, :complete_execution, workflow_step: step, most_recent: true)
      when :failure
        create(:workflow_step_transition, :error_execution, workflow_step: step, most_recent: true)
      when :retry_success
        # Create error first, then retry to pending, then back to in_progress, then complete
        create(:workflow_step_transition, :error_execution, workflow_step: step, most_recent: false)
        create(:workflow_step_transition, workflow_step: step,
                                          to_state: Tasker::Constants::WorkflowStepStatuses::PENDING, sort_key: 3, most_recent: false)
        create(:workflow_step_transition, :start_execution, workflow_step: step, sort_key: 4, most_recent: false)
        create(:workflow_step_transition, :complete_execution, workflow_step: step, sort_key: 5, most_recent: true)
      else
        # Default to success
        create(:workflow_step_transition, :complete_execution, workflow_step: step, most_recent: true)
      end
    end

    trait :successful_with_transitions do
      processed { true }
      transition_sequence { :success }
    end

    trait :failed_with_transitions do
      transition_sequence { :failure }
    end

    trait :retried_with_transitions do
      processed { true }
      transition_sequence { :retry_success }
    end
  end

  # Dummy Task Workflow Factory for testing workflow step logic
  # Mirrors the DummyTask structure from spec/mocks/dummy_task.rb
  factory :dummy_task_workflow, class: 'Tasker::Task' do
    named_task factory: %i[named_task dummy_task]
    initiator { 'pete@test' }
    source_system { 'test-system' }
    reason { 'testing!' }
    tags { %w[dummy testing] }

    transient do
      step_states { :pending }
      with_dependencies { true }
    end

    after(:create) do |task, evaluator|
      if evaluator.with_dependencies
        # ✅ FACTORY CONSISTENCY: Use find_or_create pattern to avoid conflicts
        # This handles cases where the dependent system already exists from before(:all) blocks
        dummy_system = Tasker::DependentSystem.find_or_create_by!(name: 'dummy-system') do |system|
          system.description = 'Dummy system for testing workflow step logic'
        end

        # Create named steps matching DummyTask structure
        step_one = create(:named_step, name: 'step-one', description: 'Independent Step One',
                                       dependent_system: dummy_system)
        step_two = create(:named_step, name: 'step-two', description: 'Independent Step Two',
                                       dependent_system: dummy_system)
        step_three = create(:named_step, name: 'step-three', description: 'Step Three Dependent on Step Two',
                                         dependent_system: dummy_system)
        step_four = create(:named_step, name: 'step-four', description: 'Step Four Dependent on Step Three',
                                        dependent_system: dummy_system)

        # Create workflow steps
        create(:workflow_step, evaluator.step_states, task: task, named_step: step_one, inputs: { dummy: true })
        ws2 = create(:workflow_step, evaluator.step_states, task: task, named_step: step_two, inputs: { dummy: true })
        ws3 = create(:workflow_step, evaluator.step_states, task: task, named_step: step_three, inputs: { dummy: true })
        ws4 = create(:workflow_step, evaluator.step_states, task: task, named_step: step_four, inputs: { dummy: true })

        # Create step dependencies to match DummyTask structure
        # step_three depends on step_two, step_four depends on step_three
        create(:workflow_step_edge, from_step: ws2, to_step: ws3, name: 'provides')
        create(:workflow_step_edge, from_step: ws3, to_step: ws4, name: 'provides')
      end
    end

    trait :dummy_task_two do
      named_task factory: %i[named_task dummy_task_two]
    end

    trait :with_partial_completion do
      after(:create) do |task, _evaluator|
        # Complete first two steps
        task.workflow_steps.where(named_step: { name: %w[step-one step-two] }).find_each do |step|
          step.state_machine.transition_to!(:in_progress)
          step.state_machine.transition_to!(:complete)
          step.update_columns(
            processed: true,
            processed_at: Time.current,
            results: { dummy: true, other: true }
          )
        end
      end
    end

    trait :with_step_in_progress do
      after(:create) do |task, _evaluator|
        # Set step three to in_progress
        step_three = task.workflow_steps.joins(:named_step).find_by(named_step: { name: 'step-three' })
        if step_three
          step_three.state_machine.transition_to!(:in_progress)
          step_three.update_columns(in_process: true)
        end
      end
    end

    trait :with_step_error do
      after(:create) do |task, _evaluator|
        # Set step one to error state with max retries
        step_one = task.workflow_steps.joins(:named_step).find_by(named_step: { name: 'step-one' })
        if step_one
          step_one.state_machine.transition_to!(:in_progress)
          step_one.state_machine.transition_to!(:error)
          step_one.update_columns(
            attempts: step_one.retry_limit + 1,
            results: { error: 'Test error' }
          )
        end
      end
    end
  end
end
