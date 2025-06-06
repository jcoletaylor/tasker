# frozen_string_literal: true

FactoryBot.define do
  factory :workflow_step_transition, class: 'Tasker::WorkflowStepTransition' do
    workflow_step factory: %i[workflow_step]

    # Default transition from nil to pending (initial state)
    to_state { Tasker::Constants::WorkflowStepStatuses::PENDING }
    sort_key { 0 }
    metadata { {} }
    created_at { Time.current }

    trait :initial_transition do
      to_state { Tasker::Constants::WorkflowStepStatuses::PENDING }
      sort_key { 0 }
      metadata { { initial: true, created_by: 'system' } }
    end

    trait :start_execution do
      to_state { Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS }
      sort_key { 1 }
      metadata do
        {
          triggered_by: 'step_executor',
          reason: 'step_execution_started',
          attempt: 1
        }
      end
    end

    trait :complete_execution do
      to_state { Tasker::Constants::WorkflowStepStatuses::COMPLETE }
      sort_key { 2 }
      metadata do
        {
          triggered_by: 'step_executor',
          reason: 'step_execution_successful',
          execution_time_ms: 150
        }
      end
    end

    trait :error_execution do
      to_state { Tasker::Constants::WorkflowStepStatuses::ERROR }
      sort_key { 2 }
      metadata do
        {
          triggered_by: 'step_executor',
          reason: 'step_execution_failed',
          error: 'API timeout',
          attempt: 1,
          will_retry: true
        }
      end
    end

    trait :retry_execution do
      to_state { Tasker::Constants::WorkflowStepStatuses::PENDING }
      sort_key { 3 }
      metadata do
        {
          triggered_by: 'retry_scheduler',
          reason: 'automatic_retry',
          retry_count: 1,
          backoff_seconds: 30
        }
      end
    end

    trait :cancel_execution do
      to_state { Tasker::Constants::WorkflowStepStatuses::CANCELLED }
      sort_key { 2 }
      metadata { { triggered_by: 'user', reason: 'manual_cancellation' } }
    end

    trait :manual_resolution do
      to_state { Tasker::Constants::WorkflowStepStatuses::RESOLVED_MANUALLY }
      sort_key { 3 }
      metadata do
        {
          triggered_by: 'admin_user',
          reason: 'manual_resolution',
          resolution_notes: 'Manually marked as complete due to external fix'
        }
      end
    end

    trait :skip_execution do
      to_state { Tasker::Constants::WorkflowStepStatuses::COMPLETE }
      sort_key { 1 }
      metadata do
        {
          triggered_by: 'workflow_orchestrator',
          reason: 'step_skipped',
          skip_reason: 'Bypass condition met'
        }
      end
    end

    # Execution patterns
    trait :successful_execution_sequence do
      after(:create) do |transition|
        step = transition.workflow_step

        # Create successful execution sequence
        create(:workflow_step_transition, :start_execution, workflow_step: step, sort_key: 1)
        create(:workflow_step_transition, :complete_execution, workflow_step: step, sort_key: 2)
      end
    end

    trait :failed_execution_sequence do
      after(:create) do |transition|
        step = transition.workflow_step

        # Create failed execution sequence
        create(:workflow_step_transition, :start_execution, workflow_step: step, sort_key: 1)
        create(:workflow_step_transition, :error_execution, workflow_step: step, sort_key: 2)
      end
    end

    trait :retry_then_success_sequence do
      after(:create) do |transition|
        step = transition.workflow_step

        # Create retry sequence that eventually succeeds
        create(:workflow_step_transition, :start_execution, workflow_step: step, sort_key: 1)
        create(:workflow_step_transition, :error_execution, workflow_step: step, sort_key: 2)
        create(:workflow_step_transition, :retry_execution, workflow_step: step, sort_key: 3)
        create(:workflow_step_transition, :start_execution, workflow_step: step, sort_key: 4)
        create(:workflow_step_transition, :complete_execution, workflow_step: step, sort_key: 5)
      end
    end

    trait :multiple_retries_then_failure do
      after(:create) do |transition|
        step = transition.workflow_step

        # Create multiple retry sequence that eventually fails
        create(:workflow_step_transition, :start_execution, workflow_step: step, sort_key: 1)
        create(:workflow_step_transition, :error_execution, workflow_step: step, sort_key: 2)
        create(:workflow_step_transition, :retry_execution, workflow_step: step, sort_key: 3)
        create(:workflow_step_transition, :start_execution, workflow_step: step, sort_key: 4)
        create(:workflow_step_transition, :error_execution, workflow_step: step, sort_key: 5)
        create(:workflow_step_transition, :retry_execution, workflow_step: step, sort_key: 6)
        create(:workflow_step_transition, :start_execution, workflow_step: step, sort_key: 7)
        create(:workflow_step_transition, :error_execution, workflow_step: step, sort_key: 8)
      end
    end
  end
end
