# frozen_string_literal: true

module BlogExamples
  module Post01
    module StepHandlers
      class ValidateCartHandler < Tasker::StepHandler::Base
        def process(task, sequence, step)
          # Extract and validate all required inputs
          cart_inputs = extract_and_validate_inputs(task, sequence, step)

          Rails.logger.info "Validating cart: task_id=#{task.task_id}, item_count=#{cart_inputs[:cart_items].length}"

          # Validate each item and build validated items list
          begin
            validated_items = validate_cart_items(cart_inputs[:cart_items])

            # Return raw validation results for process_results to handle
            {
              validated_items: validated_items,
              item_count: validated_items.length,
              validation_timestamp: Time.current.iso8601
            }
          rescue StandardError => e
            Rails.logger.error "Cart validation failed: #{e.message}"
            raise
          end
        end

        # Override process_results to handle business logic and result formatting
        def process_results(step, validation_response, _initial_results)
          # At this point we know the cart validation succeeded
          # Now safely calculate totals and format the business results

          validated_items = validation_response[:validated_items]

          # Calculate totals
          subtotal = validated_items.sum { |item| item[:line_total] }
          tax_rate = 0.08 # 8% tax rate
          tax = (subtotal * tax_rate).round(2)
          shipping = calculate_shipping(validated_items)
          total = subtotal + tax + shipping

          Rails.logger.info "Cart validation completed: subtotal=#{subtotal}, total=#{total}"

          step.results = {
            validated_items: validated_items,
            subtotal: subtotal,
            tax: tax,
            shipping: shipping,
            total: total,
            item_count: validated_items.length,
            validated_at: Time.current.iso8601
          }
        rescue StandardError => e
          # If result processing fails, we don't want to retry the validation
          # Log the error and set a failure result without retrying
          Rails.logger.error "Failed to process cart validation results: #{e.message}"
          step.results = {
            error: true,
            error_message: "Cart validation succeeded but result processing failed: #{e.message}",
            error_code: 'RESULT_PROCESSING_FAILED',
            raw_validation_response: validation_response,
            status: 'processing_error'
          }
        end

        private

        # Extract and validate all required inputs for cart validation
        def extract_and_validate_inputs(task, _sequence, _step)
          # Normalize all hash keys to symbols for consistent access
          context = task.context.deep_symbolize_keys
          cart_items = context[:cart_items]

          unless cart_items&.any?
            raise Tasker::PermanentError.new(
              'Cart items are required but were not provided',
              error_code: 'MISSING_CART_ITEMS'
            )
          end

          # Normalize each cart item's keys to symbols
          normalized_cart_items = cart_items.map(&:deep_symbolize_keys)

          # Validate each cart item has required fields
          normalized_cart_items.each_with_index do |item, index|
            unless item[:product_id]
              raise Tasker::PermanentError.new(
                "Product ID is required for cart item #{index + 1}",
                error_code: 'MISSING_PRODUCT_ID'
              )
            end

            next if item[:quantity]&.positive?

            raise Tasker::PermanentError.new(
              "Valid quantity is required for cart item #{index + 1}",
              error_code: 'INVALID_QUANTITY'
            )
          end

          {
            cart_items: normalized_cart_items
          }
        end

        # Validate each cart item exists and is available
        def validate_cart_items(cart_items)
          cart_items.map do |item|
            product = BlogExamples::Post01::Product.find_by(id: item[:product_id])

            unless product
              raise Tasker::PermanentError.new(
                "Product #{item[:product_id]} not found",
                error_code: 'PRODUCT_NOT_FOUND'
              )
            end

            unless product.active?
              raise Tasker::PermanentError.new(
                "Product #{product.name} is no longer available",
                error_code: 'PRODUCT_INACTIVE'
              )
            end

            if product.stock < item[:quantity]
              # Temporary failure - inventory might be updated soon
              raise Tasker::RetryableError,
                    "Insufficient stock for #{product.name}. Available: #{product.stock}, Requested: #{item[:quantity]}"
            end

            {
              product_id: product.id,
              name: product.name,
              price: product.price,
              quantity: item[:quantity],
              line_total: product.price * item[:quantity]
            }
          end
        end

        def calculate_shipping(items)
          # Simple shipping calculation
          total_weight = items.sum { |item| item[:quantity] * 0.5 } # 0.5 lbs per item

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
end
