# frozen_string_literal: true

FactoryBot.define do
  factory :dependent_system, class: 'Tasker::DependentSystem' do
    sequence(:name) { |n| "system_#{n}" }
    description { "Test dependent system for #{name}" }

    trait :api_system do
      name { 'api' }
      description { 'API integration system' }
    end

    trait :database_system do
      name { 'database' }
      description { 'Database operations system' }
    end

    trait :notification_system do
      name { 'notification' }
      description { 'Notification delivery system' }
    end

    trait :dummy_system do
      name { 'dummy-system' }
      description { 'Dummy system for testing workflow step logic' }
    end
  end
end
