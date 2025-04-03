# frozen_string_literal: true

require_relative 'step_handler'
module ApiTask
  class IntegrationExample
    include Tasker::TaskHandler

    # Constants for step names and systems
    ECOMMERCE_SYSTEM = 'ecommerce_system'
    STEP_FETCH_CART = 'fetch_cart'
    STEP_FETCH_PRODUCTS = 'fetch_products'
    STEP_VALIDATE_PRODUCTS = 'validate_products'
    STEP_CREATE_ORDER = 'create_order'
    STEP_PUBLISH_EVENT = 'publish_event'
    TASK_REGISTRY_NAME = 'api_integration_task'

    # Register the handler with concurrent processing enabled
    register_handler(TASK_REGISTRY_NAME, concurrent: true)

    define_step_templates do |templates|
      templates.define(
        dependent_system: ECOMMERCE_SYSTEM,
        name: STEP_FETCH_CART,
        description: 'Fetch cart details from e-commerce system',
        handler_class: ApiTask::StepHandler::CartFetchStepHandler,
        handler_config: Tasker::StepHandler::Api::Config.new(
          url: 'https://api.ecommerce.com/cart',
          params: {
            cart_id: 1
          }
        )
      )

      templates.define(
        dependent_system: ECOMMERCE_SYSTEM,
        name: STEP_FETCH_PRODUCTS,
        description: 'Fetch product details from product catalog',
        handler_class: ApiTask::StepHandler::ProductsFetchStepHandler,
        handler_config: Tasker::StepHandler::Api::Config.new(
          url: 'https://api.ecommerce.com/products'
        )
      )

      templates.define(
        dependent_system: ECOMMERCE_SYSTEM,
        name: STEP_VALIDATE_PRODUCTS,
        description: 'Validate product availability',
        depends_on_steps: [STEP_FETCH_PRODUCTS, STEP_FETCH_CART],
        handler_class: ApiTask::StepHandler::ProductsValidateStepHandler
      )

      templates.define(
        dependent_system: ECOMMERCE_SYSTEM,
        name: STEP_CREATE_ORDER,
        description: 'Create order from validated cart',
        depends_on_step: STEP_VALIDATE_PRODUCTS,
        handler_class: ApiTask::StepHandler::CreateOrderStepHandler
      )

      templates.define(
        dependent_system: ECOMMERCE_SYSTEM,
        name: STEP_PUBLISH_EVENT,
        description: 'Publish order created event',
        depends_on_step: STEP_CREATE_ORDER,
        handler_class: ApiTask::StepHandler::PublishEventStepHandler
      )
    end

    def schema
      @schema ||= {
        type: :object,
        required: [:cart_id],
        properties: {
          cart_id: { type: :integer }
        }
      }
    end
  end
end
