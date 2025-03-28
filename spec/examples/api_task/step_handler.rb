# frozen_string_literal: true

require_relative '../models/api/types'
require_relative '../models/api/actions'
require_relative '../models/example_order'

module ApiTask
  module StepHandler
    class CartFetchStepHandler
      def handle(task, _sequence, step)
        cart_id = task.context['cart_id']
        cart = Api::Cart.find(cart_id)
        raise "Cart not found: #{cart_id}" if cart.nil?

        step.results = { cart: cart.to_h }
      end
    end

    class ProductsFetchStepHandler
      def handle(_task, _sequence, step)
        products = Api::Product.all
        step.results = { products: products.map(&:to_h) }
      end
    end

    class ProductsValidateStepHandler
      def handle(_task, sequence, step)
        cart, products = _get_cart_and_products(sequence)
        valid_products = _valid_cart_products(cart, products)

        raise "No valid products found for cart: #{cart.id}" if valid_products.empty?

        step.results = { valid_products: valid_products.map(&:to_h) }
      end

      def _get_cart_and_products(sequence)
        cart_step = sequence.find_step_by_name(ApiTask::IntegrationTask::STEP_FETCH_CART)
        products_step = sequence.find_step_by_name(ApiTask::IntegrationTask::STEP_FETCH_PRODUCTS)

        results = [[cart_step, :cart], [products_step, :products]].map do |step, key|
          if step.nil? || step.results.empty?
            raise "Cart or products step not found or are incomplete in sequence: #{sequence.inspect}"
          end

          step.results.deep_symbolize_keys[key]
        end

        [Api::Cart.new(results[0]), results[1].map { |p| Api::Product.new(p) }]
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
        cart_step = sequence.find_step_by_name(ApiTask::IntegrationTask::STEP_FETCH_CART)
        results = cart_step.results.deep_symbolize_keys
        Api::Cart.new(results[:cart])
      end

      def _get_valid_products(sequence)
        valid_products_step = sequence.find_step_by_name(ApiTask::IntegrationTask::STEP_VALIDATE_PRODUCTS)
        results = valid_products_step.results.deep_symbolize_keys
        results[:valid_products].map { |p| Api::Product.new(p) }
      end

      def _build_order(cart, valid_products)
        ExampleOrder.new(
          id: cart.id,
          products: valid_products.map(&:to_h),
          total: _calculate_total(cart),
          discounted_total: _calculate_discounted_total(cart),
          user_id: cart.user_id
        )
      end

      def _calculate_total(cart)
        cart.products.sum do |product|
          product.quantity * Api::Product.find(product.id).price
        end
      end

      def _calculate_discounted_total(cart)
        cart.products.sum do |product|
          base_price = Api::Product.find(product.id).price
          discount = product.discount_percentage / 100
          product.quantity * (base_price * (1 - discount))
        end
      end
    end

    class PublishEventStepHandler
      def handle(_task, sequence, step)
        order_step = sequence.find_step_by_name(ApiTask::IntegrationTask::STEP_CREATE_ORDER)
        order_id = order_step.results.deep_symbolize_keys[:order_id]

        publish_results = EventBus.publish('ExampleOrderCreated', order_id)
        step.results = { published: true, publish_results: publish_results }
      end
    end
  end
end
