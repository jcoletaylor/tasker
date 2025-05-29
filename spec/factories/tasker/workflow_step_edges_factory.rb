# frozen_string_literal: true

FactoryBot.define do
  factory :workflow_step_edge, class: 'Tasker::WorkflowStepEdge' do
    from_step factory: %i[workflow_step]
    to_step factory: %i[workflow_step]
    name { 'provides' }

    # Ensure both steps belong to the same task
    after(:build) do |edge|
      if edge.from_step && edge.to_step && edge.from_step.task != edge.to_step.task
        edge.to_step.task = edge.from_step.task
      end
    end

    trait :provides_edge do
      name { 'provides' }
    end

    trait :depends_on_edge do
      name { 'depends_on' }
    end

    trait :blocks_edge do
      name { 'blocks' }
    end

    trait :triggers_edge do
      name { 'triggers' }
    end

    # Helper factory for creating edges between specific step types
    trait :cart_to_validation do
      from_step factory: %i[workflow_step fetch_cart_step]
      to_step factory: %i[workflow_step validate_products_step]
      name { 'provides' }
    end

    trait :products_to_validation do
      from_step factory: %i[workflow_step fetch_products_step]
      to_step factory: %i[workflow_step validate_products_step]
      name { 'provides' }
    end

    trait :validation_to_order do
      from_step factory: %i[workflow_step validate_products_step]
      to_step factory: %i[workflow_step create_order_step]
      name { 'provides' }
    end

    trait :order_to_event do
      from_step factory: %i[workflow_step create_order_step]
      to_step factory: %i[workflow_step publish_event_step]
      name { 'provides' }
    end
  end
end
