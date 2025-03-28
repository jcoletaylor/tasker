# frozen_string_literal: true

require_relative 'models/types'
require_relative 'models/actions'
require_relative 'models/example_order'
require_relative 'events/event_bus'

module ApiTask
  module StepHandler
    class CartFetchStepHandler
      def handle(task, _sequence, step)
        cart_id = task.context['cart_id']
        cart = ApiTask::Actions::Cart.find(cart_id)
        raise "Cart not found: #{cart_id}" if cart.nil?

        step.results = { cart: cart.to_h }
      end
    end

    class ProductsFetchStepHandler
      def handle(_task, _sequence, step)
        products = ApiTask::Actions::Product.all
        step.results = { products: products.map(&:to_h) }
      end
    end

    class ProductsValidateStepHandler
      def handle(_task, sequence, step)
        cart = _get_cart(sequence)
        products = _get_products(sequence)
        valid_products = _valid_cart_products(cart, products)

        raise "No valid products found for cart: #{cart.id}" if valid_products.empty?

        step.results = { valid_products: valid_products.map(&:to_h) }
      end

      def _get_cart(sequence)
        cart = _get_valid_step_and_results(sequence, ApiTask::IntegrationExample::STEP_FETCH_CART, :cart)
        ApiTask::Cart.new(cart)
      end

      def _get_products(sequence)
        products = _get_valid_step_and_results(sequence, ApiTask::IntegrationExample::STEP_FETCH_PRODUCTS, :products)
        products.map { |p| ApiTask::Product.new(p) }
      end

      def _get_valid_step_and_results(sequence, step_name, key)
        step = sequence.find_step_by_name(step_name)
        if step.nil? || step.results.empty?
          raise "Step or results not found or are incomplete in sequence: #{sequence.inspect}"
        end

        step.results.deep_symbolize_keys[key]
      end

      def _valid_cart_products(cart, products)
        # Create a hash of products for faster lookup
        products_map = products.index_by(&:id)

        # Map cart products to their corresponding product details
        cart.products.map do |cart_product|
          product = products_map[cart_product.id]
          unless product
            logger.error("Product from cart #{cart.id} with product ID #{cart_product.id} not found in products list")
            raise "Product with ID #{cart_product.id} not found in products list"
          end
          product
        end
      end
    end

    class CreateOrderStepHandler
      def handle(_task, sequence, step)
        cart = _get_cart(sequence)
        valid_products = _get_valid_products(sequence)

        order = _build_order(cart, valid_products)

        step.results = { order_id: order.id }
      end

      def _get_cart(sequence)
        cart_step = sequence.find_step_by_name(ApiTask::IntegrationExample::STEP_FETCH_CART)
        results = cart_step.results.deep_symbolize_keys
        ApiTask::Cart.new(results[:cart])
      end

      def _get_valid_products(sequence)
        valid_products_step = sequence.find_step_by_name(ApiTask::IntegrationExample::STEP_VALIDATE_PRODUCTS)
        results = valid_products_step.results.deep_symbolize_keys
        results[:valid_products].map { |p| ApiTask::Product.new(p) }
      end

      def _build_order(cart, valid_products)
        ApiTask::ExampleOrder.new(
          id: cart.id,
          products: valid_products.map(&:to_h),
          total: _calculate_total(cart),
          discounted_total: _calculate_discounted_total(cart),
          user_id: cart.user_id
        )
      end

      def _calculate_total(cart)
        cart.products.sum do |product|
          product.quantity * ApiTask::Actions::Product.find(product.id).price
        end
      end

      def _calculate_discounted_total(cart)
        cart.products.sum do |product|
          base_price = ApiTask::Actions::Product.find(product.id).price
          discount = product.discount_percentage / 100
          product.quantity * (base_price * (1 - discount))
        end
      end
    end

    class PublishEventStepHandler
      def handle(_task, sequence, step)
        order_step = sequence.find_step_by_name(ApiTask::IntegrationExample::STEP_CREATE_ORDER)
        order_id = order_step.results.deep_symbolize_keys[:order_id]

        publish_results = ApiTask::EventBus.publish('ExampleOrderCreated', order_id)
        step.results = { published: true, publish_results: publish_results }
      end
    end
  end
end
