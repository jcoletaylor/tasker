module BlogExamples
  module Post01
    class OrderProcessingHandler
      include Tasker::TaskHandler

      # Simplified task handler for blog example validation
      # This class demonstrates the core workflow without requiring YAML configuration



      def establish_step_dependencies_and_defaults(task, steps)
        # Note: In this simplified blog example, we don't modify step attributes
        # directly since WorkflowStep doesn't have timeout/priority attributes.
        # In a real implementation, these would be handled through:
        # 1. Step handler configuration
        # 2. Task context inspection within step handlers
        # 3. Custom step metadata

        # For blog demo purposes, we'll track these preferences in task context
        if task.context['priority'] == 'express'
          # Express order preferences tracked in context
          task.context['express_processing'] = {
            payment_timeout_ms: 15000,
            payment_retries: 1,
            email_retries: 2
          }
        end

        if task.context.dig('customer_info', 'tier') == 'premium'
          # Premium customer preferences tracked in context
          task.context['premium_processing'] = {
            priority: 'high',
            faster_processing: true
          }
        end
      end

    def update_annotations(task, sequence, steps)
      # Note: In this blog example, we skip annotations since Task model doesn't have
      # an annotations association in the test environment
      #
      # In a real implementation, this would track order processing metrics for business intelligence
      Rails.logger.info "Skipping annotations update for blog example (task_id: #{task.task_id})"

      # Original implementation would track:
      # - Payment processing metrics
      # - Completion metrics
      # - Failure analysis
      # For example validation, we just log the intent
    end

    private

    # Helper method to extract step results (updated for current API)
    def step_results(sequence, step_name)
      step = sequence.steps.find { |s| s.name == step_name }
      step&.results || {}
    end

    # Helper method to calculate step duration (processed_at is the completion time)
    def calculate_step_duration(step)
      return 0 unless step.processed_at && step.created_at
      ((step.processed_at - step.created_at) * 1000).round
    end
    end
  end
end

# Define step templates after class is loaded and constants are available
BlogExamples::Post01::OrderProcessingHandler.define_step_templates do |definer|
  definer.define(
    name: 'validate_cart',
    handler_class: BlogExamples::Post01::StepHandlers::ValidateCartHandler,
    default_retryable: true,
    default_retry_limit: 3
  )

  definer.define(
    name: 'process_payment',
    handler_class: BlogExamples::Post01::StepHandlers::ProcessPaymentHandler,
    depends_on_step: 'validate_cart',
    default_retryable: true,
    default_retry_limit: 3
  )

  definer.define(
    name: 'update_inventory',
    handler_class: BlogExamples::Post01::StepHandlers::UpdateInventoryHandler,
    depends_on_step: 'process_payment',
    default_retryable: true,
    default_retry_limit: 2
  )

  definer.define(
    name: 'create_order',
    handler_class: BlogExamples::Post01::StepHandlers::CreateOrderHandler,
    depends_on_step: 'update_inventory',
    default_retryable: true,
    default_retry_limit: 3
  )

  definer.define(
    name: 'send_confirmation',
    handler_class: BlogExamples::Post01::StepHandlers::SendConfirmationHandler,
    depends_on_step: 'create_order',
    default_retryable: true,
    default_retry_limit: 5
  )
end
