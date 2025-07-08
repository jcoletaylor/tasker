# frozen_string_literal: true

module BlogExamples
  module Post05
    module TaskHandlers
      # MonitoredCheckoutHandler demonstrates event-driven observability
      # This handler shows how workflows naturally generate events for observation
      class MonitoredCheckoutHandler < Tasker::ConfiguredTask
        def self.yaml_path
          @yaml_path ||= File.join(
            File.dirname(__FILE__),
            '..', 'config', 'monitored_checkout_handler.yaml'
          )
        end

        # Task handler for observability demonstration
        # The observability happens through event subscribers, not here
        def establish_step_dependencies_and_defaults(task, _steps)
          # Add business context for observability
          if task.context['customer_tier'] == 'premium'
            task.context['business_context'] = {
              domain: 'ecommerce',
              impact_level: 'high',
              sla_tier: 'premium'
            }
          else
            task.context['business_context'] = {
              domain: 'ecommerce',
              impact_level: 'standard',
              sla_tier: 'standard'
            }
          end

          # Add monitoring context
          task.context['monitoring_target'] = 'checkout_workflow'
          task.context['correlation_id'] ||= generate_correlation_id
        end

        def update_annotations(task, _sequence, _steps)
          # In a real implementation, this would update business annotations
          # For blog example, we just log the observability context
          Rails.logger.info "Checkout workflow completed with observability context (task_id: #{task.task_id})"
        end

        private

        def generate_correlation_id
          "checkout_#{SecureRandom.hex(8)}"
        end
      end
    end
  end
end