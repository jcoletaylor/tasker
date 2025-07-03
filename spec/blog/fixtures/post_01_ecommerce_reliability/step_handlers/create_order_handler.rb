# frozen_string_literal: true

module BlogExamples
  module Post01
    module StepHandlers
      class CreateOrderHandler < Tasker::StepHandler::Base
        def process(task, sequence, step)
          # Extract and validate all required inputs
          order_inputs = extract_and_validate_inputs(task, sequence, step)

          Rails.logger.info "Creating order: task_id=#{task.task_id}, customer=#{order_inputs[:customer_info][:email]}"

          # Create the order record - this is the core integration
          begin
            create_order_record(order_inputs, task)

            # Return raw order creation results for process_results to handle
          rescue StandardError => e
            Rails.logger.error "Order creation failed: #{e.message}"
            raise
          end
        end

        # Override process_results to handle business logic and result formatting
        def process_results(step, order_response, _initial_results)
          # At this point we know the order creation succeeded
          # Now safely format the business results

          order = order_response[:order]

          Rails.logger.info "Order created successfully: order_id=#{order.id}, order_number=#{order.order_number}"

          step.results = {
            order_id: order.id || SecureRandom.uuid,
            order_number: order.order_number,
            status: order.status,
            total_amount: order.total_amount,
            customer_email: order.customer_email,
            created_at: order.created_at&.iso8601 || Time.current.iso8601,
            estimated_delivery: calculate_estimated_delivery
          }
        rescue StandardError => e
          # If result processing fails, we don't want to retry the order creation
          # Log the error and set a failure result without retrying
          Rails.logger.error "Failed to process order creation results: #{e.message}"
          step.results = {
            error: true,
            error_message: "Order creation succeeded but result processing failed: #{e.message}",
            error_code: 'RESULT_PROCESSING_FAILED',
            raw_order_response: order_response,
            status: 'processing_error'
          }
        end

        private

        # Extract and validate all required inputs for order creation
        def extract_and_validate_inputs(task, sequence, _step)
          # Normalize all hash keys to symbols for consistent access
          customer_info = task.context['customer_info']&.deep_symbolize_keys
          cart_validation = step_results(sequence, 'validate_cart')&.deep_symbolize_keys
          payment_result = step_results(sequence, 'process_payment')&.deep_symbolize_keys
          inventory_result = step_results(sequence, 'update_inventory')&.deep_symbolize_keys

          unless customer_info
            raise Tasker::PermanentError.new(
              'Customer information is required but was not provided',
              error_code: 'MISSING_CUSTOMER_INFO'
            )
          end

          unless cart_validation&.dig(:validated_items)&.any?
            raise Tasker::PermanentError.new(
              'Cart validation results are required but were not found from validate_cart step',
              error_code: 'MISSING_CART_VALIDATION'
            )
          end

          unless payment_result&.dig(:payment_id)
            raise Tasker::PermanentError.new(
              'Payment results are required but were not found from process_payment step',
              error_code: 'MISSING_PAYMENT_RESULT'
            )
          end

          unless inventory_result&.dig(:updated_products)&.any?
            raise Tasker::PermanentError.new(
              'Inventory results are required but were not found from update_inventory step',
              error_code: 'MISSING_INVENTORY_RESULT'
            )
          end

          {
            customer_info: customer_info,
            cart_validation: cart_validation,
            payment_result: payment_result,
            inventory_result: inventory_result
          }
        end

        # Create the order record using validated inputs
        def create_order_record(order_inputs, task)
          customer_info = order_inputs[:customer_info]
          cart_validation = order_inputs[:cart_validation]
          payment_result = order_inputs[:payment_result]
          inventory_result = order_inputs[:inventory_result]

          # Create the order record (using PORO instead of ActiveRecord)
          order = BlogExamples::Post01::Order.new(
            customer_email: customer_info[:email],
            customer_name: customer_info[:name],
            customer_phone: customer_info[:phone],

            # Order totals
            subtotal: cart_validation[:subtotal],
            tax_amount: cart_validation[:tax],
            shipping_amount: cart_validation[:shipping],
            total_amount: cart_validation[:total],

            # Payment information
            payment_id: payment_result[:payment_id],
            payment_status: 'completed',
            transaction_id: payment_result[:transaction_id],

            # Order items (JSON serialized for PORO)
            items: cart_validation[:validated_items].to_json,
            item_count: cart_validation[:item_count],

            # Inventory tracking
            inventory_log_id: inventory_result[:inventory_log_id],

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
            raise Tasker::PermanentError.new(
              "Failed to create order: #{order.errors.full_messages.join(', ')}",
              error_code: 'ORDER_VALIDATION_FAILED'
            )
          end

          {
            order: order,
            creation_timestamp: Time.current.iso8601
          }
        end

        def step_results(sequence, step_name)
          step = sequence.steps.find { |s| s.name == step_name }
          step&.results || {}
        end

        def generate_order_number
          "ORD-#{Date.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
        end

        def calculate_estimated_delivery
          # Simple delivery estimation - 7 days from now (avoiding business_days dependency)
          delivery_date = 7.days.from_now
          delivery_date.strftime('%B %d, %Y')
        end
      end
    end
  end
end
