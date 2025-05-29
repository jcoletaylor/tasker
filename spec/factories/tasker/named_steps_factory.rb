# frozen_string_literal: true

FactoryBot.define do
  factory :named_step, class: 'Tasker::NamedStep' do
    sequence(:name) { |n| "test_step_#{n}" }
    description { "Test step: #{name}" }
    dependent_system

    trait :fetch_data do
      name { 'fetch_data' }
      description { 'Fetch data from external source' }
      dependent_system factory: %i[dependent_system api_system]
    end

    trait :process_data do
      name { 'process_data' }
      description { 'Process and transform data' }
      dependent_system factory: %i[dependent_system database_system]
    end

    trait :validate_data do
      name { 'validate_data' }
      description { 'Validate processed data' }
      dependent_system factory: %i[dependent_system database_system]
    end

    trait :send_notification do
      name { 'send_notification' }
      description { 'Send notification to users' }
      dependent_system factory: %i[dependent_system notification_system]
    end

    # API Integration Example steps
    trait :fetch_cart do
      name { 'fetch_cart' }
      description { 'Fetch cart from API' }
      dependent_system factory: %i[dependent_system api_system]
    end

    trait :fetch_products do
      name { 'fetch_products' }
      description { 'Fetch products from API' }
      dependent_system factory: %i[dependent_system api_system]
    end

    trait :validate_products do
      name { 'validate_products' }
      description { 'Validate product availability' }
      dependent_system factory: %i[dependent_system database_system]
    end

    trait :create_order do
      name { 'create_order' }
      description { 'Create order from cart' }
      dependent_system factory: %i[dependent_system database_system]
    end

    trait :publish_event do
      name { 'publish_event' }
      description { 'Publish order created event' }
      dependent_system factory: %i[dependent_system notification_system]
    end
  end
end
