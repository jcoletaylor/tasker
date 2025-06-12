# frozen_string_literal: true

FactoryBot.define do
  factory :named_step, class: 'Tasker::NamedStep' do
    sequence(:name) { |n| "test_step_#{n}" }
    description { "Test step: #{name}" }
    dependent_system

    trait :fetch_data do
      name { 'fetch_data' }
      dependent_system factory: %i[dependent_system api_system]
    end

    trait :process_data do
      name { 'process_data' }
      dependent_system factory: %i[dependent_system database_system]
    end

    trait :validate_data do
      name { 'validate_data' }
      dependent_system factory: %i[dependent_system database_system]
    end

    trait :send_notification do
      name { 'send_notification' }
      dependent_system factory: %i[dependent_system notification_system]
    end

    # API Integration Example steps
    trait :fetch_cart do
      name { 'fetch_cart' }
      dependent_system factory: %i[dependent_system api_system]
    end

    trait :fetch_products do
      name { 'fetch_products' }
      dependent_system factory: %i[dependent_system api_system]
    end

    trait :validate_products do
      name { 'validate_products' }
      dependent_system factory: %i[dependent_system database_system]
    end

    trait :create_order do
      name { 'create_order' }
      dependent_system factory: %i[dependent_system database_system]
    end

    trait :publish_event do
      name { 'publish_event' }
      dependent_system factory: %i[dependent_system notification_system]
    end
  end
end
