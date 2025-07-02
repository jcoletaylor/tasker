module Ecommerce
  module StepHandlers
    class ValidateCartHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        cart_items = task.context['cart_items']

        if cart_items.blank?
          Rails.logger.error "No cart items provided"
          raise StandardError, "No cart items provided"
        end

        # Validate each item exists and is available
        validated_items = cart_items.map do |item|
          product = Product.find_by(id: item['product_id'])

          unless product
            Rails.logger.error "Product not found: #{item['product_id']}"
            raise StandardError, "Product #{item['product_id']} not found"
          end

          unless product.active?
            Rails.logger.error "Product no longer available: #{product.name}"
            raise StandardError, "Product #{product.name} is no longer available"
          end

          if product.stock < item['quantity']
            # Temporary failure - inventory might be updated soon
            Rails.logger.warn "Insufficient stock for #{product.name}. Available: #{product.stock}, Requested: #{item['quantity']}"
            raise StandardError, "Insufficient stock for #{product.name}. Available: #{product.stock}, Requested: #{item['quantity']}"
          end

          {
            product_id: product.id,
            name: product.name,
            price: product.price,
            quantity: item['quantity'],
            line_total: product.price * item['quantity']
          }
        end

        # Calculate totals
        subtotal = validated_items.sum { |item| item[:line_total] }
        tax_rate = 0.08  # 8% tax rate
        tax = (subtotal * tax_rate).round(2)
        shipping = calculate_shipping(validated_items)
        total = subtotal + tax + shipping

        {
          validated_items: validated_items,
          subtotal: subtotal,
          tax: tax,
          shipping: shipping,
          total: total,
          item_count: validated_items.length,
          validated_at: Time.current.iso8601
        }
      end

      private

      def calculate_shipping(items)
        # Simple shipping calculation
        total_weight = items.sum { |item| item[:quantity] * 0.5 }  # 0.5 lbs per item

        case total_weight
        when 0..2
          5.99
        when 2..10
          9.99
        else
          14.99
        end
      end
    end
  end
end
