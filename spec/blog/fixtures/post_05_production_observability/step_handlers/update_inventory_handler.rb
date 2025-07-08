# frozen_string_literal: true

module BlogExamples
  module Post05
    module StepHandlers
      class UpdateInventoryHandler < Tasker::StepHandler::Base
        def process(task, sequence, _step)
          # Get payment results
          payment_step = sequence.find_step_by_name('process_payment')
          payment_results = payment_step&.results&.deep_symbolize_keys

          unless payment_results&.dig(:payment_successful)
            raise Tasker::PermanentError, 'Payment must be successful before updating inventory'
          end

          cart_items = task.context['cart_items'] || []

          # Simulate inventory update
          # This is where the blog post example had the timeout issue
          updated_items = cart_items.map do |item|
            # Simulate occasional inventory service issues
            # Disabled for testing to avoid randomness
            # if rand > 0.98
            #   # This simulates the production issue from the blog post
            #   sleep(30) # Inventory service timeout
            #   raise Tasker::RetryableError, "Inventory service timeout after 30 seconds"
            # end

            {
              sku: item['sku'],
              quantity_deducted: item['quantity'],
              new_stock_level: rand(0..100)
            }
          end

          {
            inventory_updated: true,
            items_updated: updated_items.count,
            updated_items: updated_items,
            updated_at: Time.current.iso8601
          }
        end

        def process_results(step, inventory_results, _initial_results)
          step.results = inventory_results
        rescue StandardError => e
          raise Tasker::PermanentError,
                "Failed to process inventory results: #{e.message}"
        end
      end
    end
  end
end
