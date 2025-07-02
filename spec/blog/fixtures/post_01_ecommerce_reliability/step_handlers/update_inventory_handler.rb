module Ecommerce
  module StepHandlers
    class UpdateInventoryHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        cart_validation = step_results(sequence, 'validate_cart')
        validated_items = cart_validation['validated_items']

        updated_products = []
        inventory_changes = []

        # Update inventory for each item
        validated_items.each do |item|
          product = Product.find(item['product_id'])

          # Double-check stock availability (race condition protection)
          if product.stock < item['quantity']
            # Temporary failure - stock might be replenished
            Rails.logger.warn "Stock changed during checkout for #{product.name}. Available: #{product.stock}, Needed: #{item['quantity']}"
            raise StandardError, "Stock changed during checkout for #{product.name}. Available: #{product.stock}, Needed: #{item['quantity']}"
          end

          # Perform atomic inventory update
          new_stock = product.stock - item['quantity']

          if product.update!(stock: new_stock)
            updated_products << {
              product_id: product.id,
              name: product.name,
              previous_stock: product.stock + item['quantity'],
              new_stock: new_stock,
              quantity_reserved: item['quantity']
            }

            inventory_changes << {
              product_id: product.id,
              change_type: 'reservation',
              quantity: -item['quantity'],
              reason: 'order_checkout',
              timestamp: Time.current.iso8601
            }
          else
            Rails.logger.warn "Failed to update inventory for #{product.name}"
            raise StandardError, "Failed to update inventory for #{product.name}"
          end
        end

        # Log inventory changes for audit trail
        InventoryLog.create!(
          changes: inventory_changes,
          task_id: task.id,
          reason: 'checkout_reservation'
        )

        {
          updated_products: updated_products,
          total_items_reserved: validated_items.sum { |item| item['quantity'] },
          inventory_log_id: InventoryLog.last.id,
          updated_at: Time.current.iso8601
        }
            rescue ActiveRecord::RecordInvalid => e
        # Temporary failure - database validation issues
        Rails.logger.warn "Database error updating inventory: #{e.message}"
        raise StandardError, "Database error updating inventory: #{e.message}"
      rescue ActiveRecord::ConnectionNotEstablished => e
        # Temporary failure - database connection issues
        Rails.logger.warn "Database connection error: #{e.message}"
        raise StandardError, "Database connection error: #{e.message}"
      end

      private

      def step_results(sequence, step_name)
        step = sequence.steps.find { |s| s.name == step_name }
        step&.results || {}
      end
    end
  end
end
