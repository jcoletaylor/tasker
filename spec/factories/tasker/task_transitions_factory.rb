# frozen_string_literal: true

FactoryBot.define do
  factory :task_transition, class: 'Tasker::TaskTransition' do
    task factory: %i[task]

    # Default transition from nil to pending (initial state)
    to_state { Tasker::Constants::TaskStatuses::PENDING }
    sort_key { 0 }
    metadata { {} }
    created_at { Time.current }

    trait :initial_transition do
      to_state { Tasker::Constants::TaskStatuses::PENDING }
      sort_key { 0 }
      metadata { { initial: true, created_by: 'system' } }
    end

    trait :start_transition do
      to_state { Tasker::Constants::TaskStatuses::IN_PROGRESS }
      sort_key { 1 }
      metadata { { triggered_by: 'task_handler', reason: 'workflow_started' } }
    end

    trait :complete_transition do
      to_state { Tasker::Constants::TaskStatuses::COMPLETE }
      sort_key { 2 }
      metadata { { triggered_by: 'workflow_orchestrator', reason: 'all_steps_complete' } }
    end

    trait :error_transition do
      to_state { Tasker::Constants::TaskStatuses::ERROR }
      sort_key { 2 }
      metadata do
        {
          triggered_by: 'error_handler',
          reason: 'step_failure',
          error_details: 'One or more steps failed',
          failed_steps: ['step_1']
        }
      end
    end

    trait :cancel_transition do
      to_state { Tasker::Constants::TaskStatuses::CANCELLED }
      sort_key { 2 }
      metadata { { triggered_by: 'user', reason: 'manual_cancellation' } }
    end

    trait :retry_transition do
      to_state { Tasker::Constants::TaskStatuses::PENDING }
      sort_key { 3 }
      metadata { { triggered_by: 'retry_scheduler', reason: 'automatic_retry', retry_count: 1 } }
    end

    trait :manual_resolution do
      to_state { Tasker::Constants::TaskStatuses::RESOLVED_MANUALLY }
      sort_key { 3 }
      metadata do
        {
          triggered_by: 'admin_user',
          reason: 'manual_resolution',
          resolution_notes: 'Resolved manually due to external system issue'
        }
      end
    end

    # Transition sequences
    trait :with_full_sequence do
      after(:create) do |transition|
        task = transition.task

        # Create a complete transition sequence
        create(:task_transition, :start_transition, task: task, sort_key: 1)
        create(:task_transition, :complete_transition, task: task, sort_key: 2)
      end
    end

    trait :with_error_sequence do
      after(:create) do |transition|
        task = transition.task

        # Create an error sequence
        create(:task_transition, :start_transition, task: task, sort_key: 1)
        create(:task_transition, :error_transition, task: task, sort_key: 2)
      end
    end

    trait :with_retry_sequence do
      after(:create) do |transition|
        task = transition.task

        # Create a retry sequence
        create(:task_transition, :start_transition, task: task, sort_key: 1)
        create(:task_transition, :error_transition, task: task, sort_key: 2)
        create(:task_transition, :retry_transition, task: task, sort_key: 3)
        create(:task_transition, :start_transition, task: task, sort_key: 4)
        create(:task_transition, :complete_transition, task: task, sort_key: 5)
      end
    end
  end
end
