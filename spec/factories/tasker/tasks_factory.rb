# frozen_string_literal: true

FactoryBot.define do
  factory :task, class: 'Tasker::Task' do
    named_task

    # Core attributes
    initiator { 'test_user' }
    source_system { 'test_system' }
    reason { 'automated_test' }
    requested_at { Time.current }

    # ✅ FIX: Add default context to prevent "Context can't be blank" validation failures
    context { { dummy: true, test: true } }

    # Default state - managed by state machine
    complete { false }

    # Optional attributes
    tags { [] }
    bypass_steps { [] }

    # State traits - these create the appropriate state machine transitions
    trait :pending do
      complete { false }
      # Status is managed by state machine - pending is the default initial state
    end

    trait :in_progress do
      complete { false }

      # Create proper state machine transitions
      after(:create) do |task|
        # Create initial transition to pending
        create(:task_transition, :initial_transition, task: task)
        # Create transition to in_progress
        create(:task_transition, :start_transition, task: task)
      end
    end

    trait :complete do
      complete { true }

      # Create proper state machine transitions
      after(:create) do |task|
        # Create initial transition to pending
        create(:task_transition, :initial_transition, task: task)
        # Create transition to in_progress
        create(:task_transition, :start_transition, task: task)
        # Create transition to complete
        create(:task_transition, :complete_transition, task: task)
      end
    end

    trait :error do
      complete { false }

      # Create proper state machine transitions
      after(:create) do |task|
        # Create initial transition to pending
        create(:task_transition, :initial_transition, task: task)
        # Create transition to in_progress
        create(:task_transition, :start_transition, task: task)
        # Create transition to error
        create(:task_transition, :error_transition, task: task)
      end
    end

    trait :cancelled do
      complete { false }

      # Create proper state machine transitions
      after(:create) do |task|
        # Create initial transition to pending
        create(:task_transition, :initial_transition, task: task)
        # Create transition to cancelled (can go directly from pending)
        create(:task_transition, :cancel_transition, task: task)
      end
    end

    # Context variations
    trait :with_cart_context do
      context { { cart_id: 12345, user_id: 67890, test: true } }
    end

    trait :with_order_context do
      context { { order_id: 98765, customer_id: 54321, test: true } }
    end

    trait :with_complex_context do
      context { {
        cart_id: 12345,
        user_id: 67890,
        order_id: 98765,
        customer_id: 54321,
        payment_method: 'credit_card',
        shipping_address: { city: 'San Francisco', state: 'CA' },
        test: true
      } }
    end

    # Task type traits
    trait :api_integration do
      named_task factory: %i[named_task api_integration]
      initiator { 'api_client' }
      source_system { 'ecommerce_api' }
      reason { 'process_cart_checkout' }
      # ✅ FIX: Add cart_id context that the test expects
      context { { cart_id: 12345, api_version: 'v2', test: true } }
    end

    trait :data_processing do
      named_task factory: %i[named_task data_processing]
      initiator { 'batch_processor' }
      source_system { 'data_pipeline' }
      reason { 'daily_batch_processing' }
    end

    trait :with_tags do
      tags { %w[urgent customer_facing revenue_impacting] }
    end

    trait :with_bypass_steps do
      bypass_steps { %w[validation_step approval_step] }
    end

    # Factory for creating tasks with workflow steps
    trait :with_steps do
      transient do
        step_count { 3 }
        step_names { (1..step_count).map { |i| "step_#{i}" } }
      end

      after(:create) do |task, evaluator|
        evaluator.step_names.each do |step_name|
          create(:workflow_step,
                 task: task,
                 named_step: create(:named_step, name: step_name))
        end
      end
    end

    # ✅ FIX: Add alias for workflow orchestration tests
    trait :with_workflow_steps do
      transient do
        step_count { 3 }
        step_names { (1..step_count).map { |i| "step_#{i}" } }
      end

      after(:create) do |task, evaluator|
        evaluator.step_names.each do |step_name|
          create(:workflow_step,
                 task: task,
                 named_step: create(:named_step, name: step_name))
        end
      end
    end

    # Complete API integration task setup
    trait :api_integration_with_steps do
      named_task factory: %i[named_task api_integration]

      after(:create) do |task|
        # Create the API integration steps in order
        fetch_cart_step = create(:named_step, :fetch_cart)
        fetch_products_step = create(:named_step, :fetch_products)
        validate_products_step = create(:named_step, :validate_products)
        create_order_step = create(:named_step, :create_order)
        publish_event_step = create(:named_step, :publish_event)

        # Create workflow steps
        step1 = create(:workflow_step, task: task, named_step: fetch_cart_step)
        step2 = create(:workflow_step, task: task, named_step: fetch_products_step)
        step3 = create(:workflow_step, task: task, named_step: validate_products_step)
        step4 = create(:workflow_step, task: task, named_step: create_order_step)
        step5 = create(:workflow_step, task: task, named_step: publish_event_step)

        # Set up dependencies (step3 depends on step1 and step2, step4 depends on step3, step5 depends on step4)
        create(:workflow_step_edge, from_step: step1, to_step: step3)
        create(:workflow_step_edge, from_step: step2, to_step: step3)
        create(:workflow_step_edge, from_step: step3, to_step: step4)
        create(:workflow_step_edge, from_step: step4, to_step: step5)
      end
    end
  end
end
