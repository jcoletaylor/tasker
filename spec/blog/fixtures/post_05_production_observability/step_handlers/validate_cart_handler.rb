# frozen_string_literal: true

module BlogExamples
  module Post05
    module StepHandlers
      class ValidateCartHandler < Tasker::StepHandler::Base
        def process(task, _sequence, _step)
          # Simple cart validation logic
          # The real observability happens through events

          cart_items = task.context['cart_items'] || []

          # Validate cart has items
          raise Tasker::PermanentError, 'Cart is empty' if cart_items.empty?

          # Calculate total
          total = cart_items.sum { |item| item['price'] * item['quantity'] }

          # Return validation results
          {
            validated: true,
            item_count: cart_items.count,
            cart_total: total,
            validated_at: Time.current.iso8601
          }
        end

        def process_results(step, validation_results, _initial_results)
          step.results = validation_results
        rescue StandardError => e
          raise Tasker::PermanentError,
                "Failed to process cart validation results: #{e.message}"
        end
      end
    end
  end
end
