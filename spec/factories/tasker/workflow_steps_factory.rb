# frozen_string_literal: true

FactoryBot.define do
  factory :workflow_step, class: 'Tasker::WorkflowStep' do
    task
    named_step

    # Core attributes
    retryable { true }
    retry_limit { 3 }
    skippable { false }
    in_process { false }
    processed { false }
    attempts { 0 }

    # Dynamic attributes
    inputs { |step| step.task&.context || {} }
    results { {} }

    # State traits - these create the appropriate state machine transitions
    trait :pending do
      processed { false }
      in_process { false }
      # Status is managed by state machine - pending is the default initial state
    end

    trait :in_progress do
      processed { false }
      in_process { true }
      attempts { 1 }
      last_attempted_at { Time.current }

      # Create proper state machine transitions
      after(:create) do |step|
        # Create initial transition to pending (not most recent)
        create(:workflow_step_transition, :initial_transition, workflow_step: step, most_recent: false)
        # Create transition to in_progress (this is most recent)
        create(:workflow_step_transition, :start_execution, workflow_step: step, most_recent: true)
      end
    end

    trait :complete do
      processed { true }
      in_process { false }
      processed_at { Time.current }
      results { { success: true, message: 'Step completed successfully' } }

      # Create proper state machine transitions
      after(:create) do |step|
        # Create initial transition to pending (not most recent)
        create(:workflow_step_transition, :initial_transition, workflow_step: step, most_recent: false)
        # Create transition to in_progress (not most recent)
        create(:workflow_step_transition, :start_execution, workflow_step: step, most_recent: false)
        # Create transition to complete (this is most recent)
        create(:workflow_step_transition, :complete_execution, workflow_step: step, most_recent: true)
      end
    end

    trait :error do
      processed { false }
      in_process { false }
      attempts { 1 }
      last_attempted_at { Time.current }
      results { { error: 'Step failed', message: 'An error occurred during step execution' } }

      # Create proper state machine transitions
      after(:create) do |step|
        # Create initial transition to pending (not most recent)
        create(:workflow_step_transition, :initial_transition, workflow_step: step, most_recent: false)
        # Create transition to in_progress (not most recent)
        create(:workflow_step_transition, :start_execution, workflow_step: step, most_recent: false)
        # Create transition to error (this is most recent)
        create(:workflow_step_transition, :error_execution, workflow_step: step, most_recent: true)
      end
    end

    trait :cancelled do
      processed { false }
      in_process { false }

      # Create proper state machine transitions
      after(:create) do |step|
        # Create initial transition to pending (not most recent)
        create(:workflow_step_transition, :initial_transition, workflow_step: step, most_recent: false)
        # Create transition to cancelled (this is most recent)
        create(:workflow_step_transition, workflow_step: step,
                                          to_state: Tasker::Constants::WorkflowStepStatuses::CANCELLED, sort_key: 1, most_recent: true)
      end
    end

    trait :resolved_manually do
      processed { true }
      in_process { false }
      results { { resolved_manually: true, resolution_reason: 'Manual intervention' } }

      # Create proper state machine transitions
      after(:create) do |step|
        # Create initial transition to pending (not most recent)
        create(:workflow_step_transition, :initial_transition, workflow_step: step, most_recent: false)
        # Create transition to in_progress (not most recent)
        create(:workflow_step_transition, :start_execution, workflow_step: step, most_recent: false)
        # Create transition to error (not most recent)
        create(:workflow_step_transition, :error_execution, workflow_step: step, most_recent: false)
        # Create transition to resolved_manually (this is most recent)
        create(:workflow_step_transition, workflow_step: step,
                                          to_state: Tasker::Constants::WorkflowStepStatuses::RESOLVED_MANUALLY, sort_key: 3, most_recent: true)
      end
    end

    # Retry configuration traits
    trait :non_retryable do
      retryable { false }
      retry_limit { 0 }
    end

    trait :high_retry_limit do
      retry_limit { 10 }
    end

    trait :skippable_step do
      skippable { true }
    end

    trait :with_backoff do
      backoff_request_seconds { 30 }
      last_attempted_at { 1.minute.ago }
    end

    trait :max_retries_reached do
      attempts { 3 }
      retry_limit { 3 }
      status { Tasker::Constants::WorkflowStepStatuses::ERROR }
      results { { error: 'Max retries reached', attempts: 3 } }
    end

    # Results variations
    trait :with_api_results do
      results do
        {
          api_response: {
            status: 200,
            data: { id: 123, name: 'Test Item' },
            headers: { 'content-type' => 'application/json' }
          },
          execution_time_ms: 150
        }
      end
    end

    trait :with_processing_results do
      results do
        {
          records_processed: 100,
          records_failed: 2,
          processing_time_ms: 5000,
          summary: 'Batch processing completed with minor errors'
        }
      end
    end

    trait :with_validation_results do
      results do
        {
          validation_passed: true,
          items_validated: 5,
          validation_errors: [],
          validation_warnings: ['Item quantity adjusted']
        }
      end
    end

    # Step type traits based on named_step
    trait :fetch_cart_step do
      named_step factory: %i[named_step fetch_cart]
      inputs { { cart_id: 1 } }
    end

    trait :fetch_products_step do
      named_step factory: %i[named_step fetch_products]
      inputs { {} }
    end

    trait :validate_products_step do
      named_step factory: %i[named_step validate_products]
      inputs { { cart: { id: 1, items: [] }, products: [] } }
    end

    trait :create_order_step do
      named_step factory: %i[named_step create_order]
      inputs { { cart: { id: 1 }, validated_products: [] } }
    end

    trait :publish_event_step do
      named_step factory: %i[named_step publish_event]
      inputs { { order_id: 123 } }
    end

    # Composite traits for common scenarios
    trait :successful_api_call do
      complete
      with_api_results
      attempts { 1 }
      processed_at { Time.current }
    end

    trait :failed_with_retry do
      error
      attempts { 2 }
      retry_limit { 3 }
      last_attempted_at { 30.seconds.ago }
      results { { error: 'Temporary failure', retry_after: 60 } }
    end

    trait :completed_after_retry do
      complete
      attempts { 2 }
      processed_at { Time.current }
      results { { success: true, message: 'Succeeded after retry', attempts: 2 } }
    end
  end
end
