# frozen_string_literal: true

FactoryBot.define do
  factory :named_task, class: 'Tasker::NamedTask' do
    sequence(:name) { |n| "test_task_#{n}" }
    description { "Test task: #{name}" }

    trait :api_integration do
      name { 'api_integration_example' }
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
  end
end
