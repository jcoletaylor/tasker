module BlogExamples
  module Post01
    module StepHandlers
      class UpdateInventoryHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        cart_validation = step_results(sequence, 'validate_cart')
        validated_items = cart_validation['validated_items']

        updated_products = []
        inventory_changes = []

        # Update inventory for each item using mock service for blog validation
        validated_items.each do |item|
          product = Product.find(item['product_id'])

          # Check availability using mock service
          availability_result = MockInventoryService.check_availability(
            product_id: product.id,
            quantity: item['quantity']
          )

          unless availability_result[:available]
            Rails.logger.warn "Stock not available for #{product.name}. Available: #{availability_result[:stock_level]}, Needed: #{item['quantity']}"
            raise StandardError, "Stock not available for #{product.name}. Available: #{availability_result[:stock_level]}, Needed: #{item['quantity']}"
          end

          # Reserve inventory using mock service
          reservation_result = MockInventoryService.reserve_inventory(
            product_id: product.id,
            quantity: item['quantity'],
            order_id: "order_#{task.task_id}",
            customer_id: task.context['customer_info']['id']
          )

          if reservation_result[:status] == 'reserved'
            updated_products << {
              product_id: product.id,
              name: product.name,
              previous_stock: availability_result[:stock_level],
              new_stock: availability_result[:stock_level] - item['quantity'],
              quantity_reserved: item['quantity'],
              reservation_id: reservation_result[:reservation_id]
            }

            inventory_changes << {
              product_id: product.id,
              change_type: 'reservation',
              quantity: -item['quantity'],
              reason: 'order_checkout',
              timestamp: Time.current.iso8601,
              reservation_id: reservation_result[:reservation_id]
            }

            # Update the PORO model stock for consistency
            product.stock = availability_result[:stock_level] - item['quantity']
          else
            Rails.logger.warn "Failed to reserve inventory for #{product.name}"
            raise StandardError, "Failed to reserve inventory for #{product.name}"
          end
        end

        # Note: In a real implementation, you would log inventory changes to an audit trail
        # For this blog example, we'll skip the audit logging to avoid additional dependencies
        # InventoryLog.create!(changes: inventory_changes, task_id: task.id, reason: 'checkout_reservation')

        {
          updated_products: updated_products,
          total_items_reserved: validated_items.sum { |item| item['quantity'] },
          inventory_changes: inventory_changes,
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
end
