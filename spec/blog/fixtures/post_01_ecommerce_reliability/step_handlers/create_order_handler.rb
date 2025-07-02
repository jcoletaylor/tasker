module BlogExamples
  module Post01
    module StepHandlers
      class CreateOrderHandler < Tasker::StepHandler::Base
        def process(task, sequence, step)
          customer_info = task.context['customer_info']
          cart_validation = step_results(sequence, 'validate_cart')
          payment_result = step_results(sequence, 'process_payment')
          inventory_result = step_results(sequence, 'update_inventory')

          # Create the order record (using PORO instead of ActiveRecord)
          order = BlogExamples::Post01::Order.new(
          customer_email: customer_info['email'],
          customer_name: customer_info['name'],
          customer_phone: customer_info['phone'],

          # Order totals
          subtotal: cart_validation['subtotal'],
          tax_amount: cart_validation['tax'],
          shipping_amount: cart_validation['shipping'],
          total_amount: cart_validation['total'],

          # Payment information
          payment_id: payment_result['payment_id'],
          payment_status: 'completed',
          transaction_id: payment_result['transaction_id'],

          # Order items (JSON serialized for PORO)
          items: cart_validation['validated_items'].to_json,
          item_count: cart_validation['item_count'],

          # Inventory tracking
          inventory_log_id: inventory_result['inventory_log_id'],

          # Order metadata
          status: 'confirmed',
          order_number: generate_order_number,
          placed_at: Time.current,

          # Tracking
          task_id: task.id,
          workflow_version: '1.0.0',

          # Timestamps for PORO
          created_at: Time.current,
          updated_at: Time.current
        )

        # Validate the order
        unless order.valid?
          raise StandardError, "Failed to create order: #{order.errors.full_messages.join(', ')}"
        end

        {
          order_id: order.id || SecureRandom.uuid,
          order_number: order.order_number,
          status: order.status,
          total_amount: order.total_amount,
          customer_email: order.customer_email,
          created_at: order.created_at&.iso8601 || Time.current.iso8601,
          estimated_delivery: calculate_estimated_delivery
        }
      rescue => e
        # Handle any validation or processing errors
        Rails.logger.warn "Failed to create order: #{e.message}"
        raise StandardError, "Failed to create order: #{e.message}"
        end

        private

        def step_results(sequence, step_name)
          step = sequence.steps.find { |s| s.name == step_name }
          step&.results || {}
        end

        def generate_order_number
          "ORD-#{Date.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
        end

        def calculate_estimated_delivery
          # Simple delivery estimation - 7 days from now (avoiding business_days dependency)
          delivery_date = Time.current + 7.days
          delivery_date.strftime('%B %d, %Y')
        end
      end
    end
  end
end
