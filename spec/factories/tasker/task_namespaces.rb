# frozen_string_literal: true

FactoryBot.define do
  factory :task_namespace, class: 'Tasker::TaskNamespace' do
    sequence(:name) { |n| "namespace_#{n}" }
    description { "Test namespace: #{name}" }

    trait :default do
      name { 'default' }
      description { 'Default task namespace' }
    end

    trait :payments do
      name { 'payments' }
      description { 'Payment processing and financial tasks' }
    end

    trait :notifications do
      name { 'notifications' }
      description { 'Notification and communication tasks' }
    end

    trait :integrations do
      name { 'integrations' }
      description { 'Third-party API integration tasks' }
    end

    trait :data_processing do
      name { 'data_processing' }
      description { 'ETL and data transformation tasks' }
    end

    trait :reporting do
      name { 'reporting' }
      description { 'Report generation and analytics tasks' }
    end
  end
end
