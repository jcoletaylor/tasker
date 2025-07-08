# frozen_string_literal: true

module BlogExamples
  module Post05
    module StepHandlers
      class CreateOrderHandler < Tasker::StepHandler::Base
        def process(task, sequence, _step)
          # Get previous step results
          payment_step = sequence.find_step_by_name('process_payment')
          payment_results = payment_step&.results&.deep_symbolize_keys

          inventory_step = sequence.find_step_by_name('update_inventory')
          inventory_results = inventory_step&.results&.deep_symbolize_keys

          unless inventory_results&.dig(:inventory_updated)
            raise Tasker::PermanentError, 'Inventory must be updated before creating order'
          end

          # Create order record
          order_id = "order_#{SecureRandom.hex(8)}"

          {
            order_created: true,
            order_id: order_id,
            payment_id: payment_results[:payment_id],
            customer_id: task.context['customer_id'],
            customer_tier: task.context['customer_tier'],
            order_value: payment_results[:amount],
            items_count: inventory_results[:items_updated],
            created_at: Time.current.iso8601
          }
        end

        def process_results(step, order_results, _initial_results)
          step.results = order_results
        rescue StandardError => e
          raise Tasker::PermanentError,
                "Failed to process order creation results: #{e.message}"
        end
      end
    end
  end
end
