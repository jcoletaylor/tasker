# frozen_string_literal: true

module BlogExamples
  module Post01
    # OrderProcessingHandler demonstrates YAML-driven task configuration
    # This example shows the ConfiguredTask pattern for modern Tasker applications
    class OrderProcessingHandler < Tasker::ConfiguredTask
      def self.yaml_path
        @yaml_path ||= File.join(
          File.dirname(__FILE__),
          '..', 'config', 'order_processing_handler.yaml'
        )
      end

      # Simplified task handler for blog example validation
      # This class demonstrates the core workflow without requiring complex configuration
      def establish_step_dependencies_and_defaults(task, _steps)
        # NOTE: In this simplified blog example, we don't modify step attributes
        # directly since WorkflowStep doesn't have timeout/priority attributes.
        # In a real implementation, these would be handled through:
        # 1. Step handler configuration (now in YAML handler_config)
        # 2. Task context inspection within step handlers
        # 3. Custom step metadata

        # For blog demo purposes, we'll track these preferences in task context
        if task.context['priority'] == 'express'
          # Express order preferences tracked in context
          task.context['express_processing'] = {
            payment_timeout_ms: 15_000,
            payment_retries: 1,
            email_retries: 2
          }
        end

        return unless task.context.dig('customer_info', 'tier') == 'premium'

        # Premium customer preferences tracked in context
        task.context['premium_processing'] = {
          priority: 'high',
          faster_processing: true
        }
      end

      def update_annotations(task, _sequence, _steps)
        # NOTE: In this blog example, we skip annotations since Task model doesn't have
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
    end
  end
end
