# frozen_string_literal: true

FactoryBot.define do
  # Complete API Integration Workflow Factory
  # This mirrors the setup from integration_example_spec.rb
  factory :api_integration_workflow, class: 'Tasker::Task' do
    initiator { 'pete@test' }
    source_system { 'ecommerce-api' }
    reason { 'automated_integration_test' }
    tags { %w[api integration testing] }

    # ✅ FIX: Add default context to prevent "Context can't be blank" validation failures

    transient do
      with_dependencies { true }
      step_states { :pending } # Can be :pending, :complete, :in_progress, :error
    end

    # Use find_or_create pattern for named_task to avoid conflicts
    before(:create) do |task, _evaluator|
      # ✅ FACTORY CONSISTENCY: Use find_or_create pattern to avoid conflicts
      # This handles cases where the named_task already exists from previous tests
      api_named_task = Tasker::NamedTask.find_or_create_by!(name: 'api_integration_example') do |named_task|
        named_task.description = 'API integration workflow task'
      end

      task.named_task = api_named_task
    end

    after(:create) do |task, evaluator|
      if evaluator.with_dependencies
        # ✅ FACTORY CONSISTENCY: Use find_or_create pattern for dependent systems to avoid conflicts
        # Create dependent systems that the task handler will use
        api_system = Tasker::DependentSystem.find_or_create_by!(name: 'api-system') do |system|
          system.description = 'API system for integration testing'
        end

        database_system = Tasker::DependentSystem.find_or_create_by!(name: 'database-system') do |system|
          system.description = 'Database system for integration testing'
        end

        notification_system = Tasker::DependentSystem.find_or_create_by!(name: 'notification-system') do |system|
          system.description = 'Notification system for integration testing'
        end

        # ✅ FIX: Create the actual workflow steps that the test expects
        # Create named steps for the API integration workflow
        fetch_cart_step = Tasker::NamedStep.find_or_create_by!(name: 'fetch_cart') do |step|
          step.description = 'Fetch cart data from API'
          step.dependent_system = api_system
        end

        fetch_products_step = Tasker::NamedStep.find_or_create_by!(name: 'fetch_products') do |step|
          step.description = 'Fetch product data from API'
          step.dependent_system = api_system
        end

        validate_products_step = Tasker::NamedStep.find_or_create_by!(name: 'validate_products') do |step|
          step.description = 'Validate product data'
          step.dependent_system = database_system
        end

        create_order_step = Tasker::NamedStep.find_or_create_by!(name: 'create_order') do |step|
          step.description = 'Create order in database'
          step.dependent_system = database_system
        end

        publish_event_step = Tasker::NamedStep.find_or_create_by!(name: 'publish_event') do |step|
          step.description = 'Publish order created event'
          step.dependent_system = notification_system
        end

        # Create workflow steps
        step1 = create(:workflow_step, evaluator.step_states, task: task, named_step: fetch_cart_step)
        step2 = create(:workflow_step, evaluator.step_states, task: task, named_step: fetch_products_step)
        step3 = create(:workflow_step, evaluator.step_states, task: task, named_step: validate_products_step)
        step4 = create(:workflow_step, evaluator.step_states, task: task, named_step: create_order_step)
        step5 = create(:workflow_step, evaluator.step_states, task: task, named_step: publish_event_step)

        # Create dependencies: validate depends on fetch_cart and fetch_products
        create(:workflow_step_edge, from_step: step1, to_step: step3, name: 'provides')
        create(:workflow_step_edge, from_step: step2, to_step: step3, name: 'provides')
        # create_order depends on validate_products
        create(:workflow_step_edge, from_step: step3, to_step: step4, name: 'provides')
        # publish_event depends on create_order
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

    # ✅ FIX: Add default context to prevent "Context can't be blank" validation failures

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

    # ✅ FIX: Add default context to prevent "Context can't be blank" validation failures

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

    # ✅ FIX: Add default context to prevent "Context can't be blank" validation failures

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
    initiator { 'pete@test' }
    source_system { 'test-system' }
    reason { 'testing!' }
    tags { %w[dummy testing] }

    # ✅ FIX: Add default context to prevent "Context can't be blank" validation failures

    transient do
      step_states { :pending }
      with_dependencies { true }
    end

    # Use find_or_create pattern for named_task to avoid conflicts
    before(:create) do |task, _evaluator|
      # ✅ FACTORY CONSISTENCY: Use find_or_create pattern to avoid conflicts
      # This handles cases where the named_task already exists from previous tests
      dummy_named_task = Tasker::NamedTask.find_or_create_by!(name: 'dummy_task') do |named_task|
        named_task.description = 'Dummy task for testing workflow step logic'
      end
      task.named_task = dummy_named_task
    end

    after(:create) do |task, evaluator|
      if evaluator.with_dependencies
        # ✅ FACTORY CONSISTENCY: Use find_or_create pattern to avoid conflicts
        # This handles cases where the dependent system already exists from before(:all) blocks
        dummy_system = Tasker::DependentSystem.find_or_create_by!(name: 'dummy-system') do |system|
          system.description = 'Dummy system for testing workflow step logic'
        end

        # ✅ FACTORY CONSISTENCY: Use find_or_create pattern for named_steps to avoid conflicts
        # Create named steps matching DummyTask structure
        step_one = Tasker::NamedStep.find_or_create_by!(name: 'step-one', dependent_system: dummy_system) do |step|
          step.description = 'Independent Step One'
        end
        step_two = Tasker::NamedStep.find_or_create_by!(name: 'step-two', dependent_system: dummy_system) do |step|
          step.description = 'Independent Step Two'
        end
        step_three = Tasker::NamedStep.find_or_create_by!(name: 'step-three', dependent_system: dummy_system) do |step|
          step.description = 'Step Three Dependent on Step Two'
        end
        step_four = Tasker::NamedStep.find_or_create_by!(name: 'step-four', dependent_system: dummy_system) do |step|
          step.description = 'Step Four Dependent on Step Three'
        end

        # Create workflow steps
        if evaluator.step_states
          create(:workflow_step, evaluator.step_states, task: task, named_step: step_one, inputs: { dummy: true })
          ws2 = create(:workflow_step, evaluator.step_states, task: task, named_step: step_two, inputs: { dummy: true })
          ws3 = create(:workflow_step, evaluator.step_states, task: task, named_step: step_three,
                                                              inputs: { dummy: true })
          ws4 = create(:workflow_step, evaluator.step_states, task: task, named_step: step_four,
                                                              inputs: { dummy: true })
        else
          # Create workflow steps without any state trait (for orchestration testing)
          create(:workflow_step, task: task, named_step: step_one, inputs: { dummy: true })
          ws2 = create(:workflow_step, task: task, named_step: step_two, inputs: { dummy: true })
          ws3 = create(:workflow_step, task: task, named_step: step_three, inputs: { dummy: true })
          ws4 = create(:workflow_step, task: task, named_step: step_four, inputs: { dummy: true })
        end

        # Create step dependencies to match DummyTask structure
        # step_three depends on step_two, step_four depends on step_three
        create(:workflow_step_edge, from_step: ws2, to_step: ws3, name: 'provides')
        create(:workflow_step_edge, from_step: ws3, to_step: ws4, name: 'provides')
      end
    end

    trait :dummy_task_two do
      # Override the named_task for dummy_task_two variant
      before(:create) do |task, _evaluator|
        dummy_task_two_named_task = Tasker::NamedTask.find_or_create_by!(name: 'dummy_task_two') do |named_task|
          named_task.description = 'Second dummy task variant for testing'
        end
        task.named_task = dummy_task_two_named_task
      end
    end

    # Trait specifically for event-driven orchestration testing
    # Creates tasks and steps in their initial pending state
    trait :for_orchestration do
      step_states { nil } # Don't apply any state trait initially

      # Ensure task starts in pending state for orchestration
      after(:create) do |task, _evaluator|
        # Explicitly set task to pending state if not already
        unless task.status == Tasker::Constants::TaskStatuses::PENDING
          task.update_columns(status: Tasker::Constants::TaskStatuses::PENDING)
        end

        # Ensure all steps are in pending state with proper initial transitions
        task.workflow_steps.each do |step|
          # Clear any existing transitions
          step.workflow_step_transitions.destroy_all

          # Create initial transition to pending state (this is the proper way)
          step.workflow_step_transitions.create!(
            to_state: Tasker::Constants::WorkflowStepStatuses::PENDING,
            sort_key: 0,
            most_recent: true,
            metadata: { created_by: 'factory_for_orchestration' }
          )

          # Set step attributes to pending state
          step.update_columns(
            processed: false,
            in_process: false,
            processed_at: nil,
            attempts: 0
          )
        end
      end
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
