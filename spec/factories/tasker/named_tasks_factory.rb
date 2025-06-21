# frozen_string_literal: true

FactoryBot.define do
  factory :named_task, class: 'Tasker::NamedTask' do
    sequence(:name) { |n| "test_task_#{n}" }
    description { "Test task: #{name}" }
    version { '0.1.0' }

    # Association with default namespace
    task_namespace { Tasker::TaskNamespace.default }

    # Use consistent names for traits that need handler factory integration
    trait :api_integration do
      name { 'api_integration_task' }
      description { 'API integration workflow task' }
    end

    trait :data_processing do
      name { 'data_processing_task' }
      description { 'Data processing and transformation task' }
    end

    trait :notification_task do
      name { 'notification_delivery' }
      description { 'Notification delivery task' }
    end

    trait :simple_workflow do
      name { 'simple_workflow' }
      description { 'Simple linear workflow for testing' }
    end

    trait :dummy_task do
      name { 'dummy_task' }
      description { 'Dummy task for testing workflow step logic' }
    end

    trait :dummy_task_two do
      name { 'dummy_task_two' }
      description { 'Second dummy task variant for testing' }
    end

    trait :api_integration_example do
      name { 'api_integration_example' }
      description { 'API integration example task' }
    end

    # Versioning traits
    trait :version_1_0 do
      version { '1.0.0' }
    end

    trait :version_2_0 do
      version { '2.0.0' }
    end

    # Custom namespace traits
    trait :payments_namespace do
      task_namespace { create(:task_namespace, name: 'payments', description: 'Payment processing tasks') }
    end

    trait :notifications_namespace do
      task_namespace { create(:task_namespace, name: 'notifications', description: 'Notification tasks') }
    end
  end
end
