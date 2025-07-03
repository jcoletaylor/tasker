# frozen_string_literal: true

module BlogExamples
  module Post01
    module StepHandlers
      class UpdateInventoryHandler < Tasker::StepHandler::Base
        def process(task, sequence, step)
          # Extract and validate all required inputs
          inventory_inputs = extract_and_validate_inputs(task, sequence, step)

          Rails.logger.info "Updating inventory: task_id=#{task.task_id}, item_count=#{inventory_inputs[:validated_items].length}"

          # Process inventory reservations - this is the core integration
          begin
            process_inventory_reservations(
              inventory_inputs[:validated_items],
              inventory_inputs[:customer_info],
              task.task_id
            )
          rescue StandardError => e
            Rails.logger.error "Inventory update failed: #{e.message}"
            raise
          end
        end

        # Override process_results to handle business logic and result formatting
        def process_results(step, reservation_response, _initial_results)
          # At this point we know the inventory reservations succeeded
          # Now safely format the business results

          updated_products = reservation_response[:updated_products]
          inventory_changes = reservation_response[:inventory_changes]

          Rails.logger.info "Inventory update completed: products_updated=#{updated_products.length}"

          step.results = {
            updated_products: updated_products,
            total_items_reserved: updated_products.sum { |product| product[:quantity_reserved] },
            inventory_changes: inventory_changes,
            updated_at: Time.current.iso8601
          }
        rescue StandardError => e
          # If result processing fails, we don't want to retry the inventory updates
          # Log the error and set a failure result without retrying
          Rails.logger.error "Failed to process inventory update results: #{e.message}"
          step.results = {
            error: true,
            error_message: "Inventory update succeeded but result processing failed: #{e.message}",
            error_code: 'RESULT_PROCESSING_FAILED',
            raw_reservation_response: reservation_response,
            status: 'processing_error'
          }
        end

        private

        # Extract and validate all required inputs for inventory processing
        def extract_and_validate_inputs(task, sequence, _step)
          # Normalize all hash keys to symbols for consistent access
          cart_validation = step_results(sequence, 'validate_cart')&.deep_symbolize_keys
          customer_info = task.context['customer_info']&.deep_symbolize_keys

          unless cart_validation&.dig(:validated_items)&.any?
            raise Tasker::PermanentError.new(
              'Validated cart items are required but were not found from validate_cart step',
              error_code: 'MISSING_VALIDATED_ITEMS'
            )
          end

          unless customer_info
            raise Tasker::PermanentError.new(
              'Customer information is required but was not provided',
              error_code: 'MISSING_CUSTOMER_INFO'
            )
          end

          {
            validated_items: cart_validation[:validated_items],
            customer_info: customer_info
          }
        end

        # Process inventory reservations for all validated items
        def process_inventory_reservations(validated_items, customer_info, task_id)
          updated_products = []
          inventory_changes = []

          # Update inventory for each item using mock service for blog validation
          validated_items.each do |item|
            product = Product.find(item[:product_id])

            # Check availability using mock service
            availability_result = MockInventoryService.check_availability(
              product_id: product.id,
              quantity: item[:quantity]
            )

            unless availability_result[:available]
              raise Tasker::RetryableError,
                    "Stock not available for #{product.name}. Available: #{availability_result[:stock_level]}, Needed: #{item[:quantity]}"
            end

            # Reserve inventory using mock service
            reservation_result = MockInventoryService.reserve_inventory(
              product_id: product.id,
              quantity: item[:quantity],
              order_id: "order_#{task_id}",
              customer_id: customer_info[:id]
            )

            ensure_reservation_successful!(reservation_result, product.name)

            updated_products << {
              product_id: product.id,
              name: product.name,
              previous_stock: availability_result[:stock_level],
              new_stock: availability_result[:stock_level] - item[:quantity],
              quantity_reserved: item[:quantity],
              reservation_id: reservation_result[:reservation_id]
            }

            inventory_changes << {
              product_id: product.id,
              change_type: 'reservation',
              quantity: -item[:quantity],
              reason: 'order_checkout',
              timestamp: Time.current.iso8601,
              reservation_id: reservation_result[:reservation_id]
            }

            # Update the PORO model stock for consistency
            product.stock = availability_result[:stock_level] - item[:quantity]
          end

          {
            updated_products: updated_products,
            inventory_changes: inventory_changes,
            reservation_timestamp: Time.current.iso8601
          }
        rescue ActiveRecord::RecordInvalid => e
          # Temporary failure - database validation issues
          raise Tasker::RetryableError, "Database error updating inventory: #{e.message}"
        rescue ActiveRecord::ConnectionNotEstablished => e
          # Temporary failure - database connection issues
          raise Tasker::RetryableError, "Database connection error: #{e.message}"
        end

        # Ensure inventory reservation was successful
        def ensure_reservation_successful!(reservation_result, product_name)
          case reservation_result[:status]
          when 'reserved'
            # Success - continue processing
            nil
          when 'insufficient_stock'
            # Temporary failure - stock might be replenished
            raise Tasker::RetryableError, "Insufficient stock for #{product_name}"
          when 'reservation_failed'
            # Temporary failure - reservation system issue
            raise Tasker::RetryableError, "Failed to reserve inventory for #{product_name}"
          else
            # Unknown status - treat as retryable for safety
            raise Tasker::RetryableError,
                  "Unknown reservation status for #{product_name}: #{reservation_result[:status]}"
          end
        end

        def step_results(sequence, step_name)
          step = sequence.steps.find { |s| s.name == step_name }
          step&.results || {}
        end
      end
    end
  end
end
