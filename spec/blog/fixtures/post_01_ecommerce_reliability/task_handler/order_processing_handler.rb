module Ecommerce
  class OrderProcessingHandler < Tasker::ConfiguredTask
    # Configuration is driven by the YAML file: config/order_processing_handler.yaml
    # This class handles runtime behavior and enterprise features

    def establish_step_dependencies_and_defaults(task, steps)
      # Add runtime optimizations based on order context
      if task.context['priority'] == 'express'
        # Express orders get faster timeouts and fewer retries
        payment_step = steps.find { |s| s.name == 'process_payment' }
        payment_step&.update(timeout: 15000, retry_limit: 1)

        email_step = steps.find { |s| s.name == 'send_confirmation' }
        email_step&.update(retry_limit: 2)
      end

      # Add customer tier optimizations
      if task.context.dig('customer_info', 'tier') == 'premium'
        # Premium customers get priority processing
        steps.each { |step| step.update(priority: 'high') }
      end
    end

    def update_annotations(task, sequence, steps)
      # Track order processing metrics for business intelligence
      payment_step = steps.find { |s| s.name == 'process_payment' }
      if payment_step&.status == 'complete'
        payment_results = payment_step.results

        task.annotations.create!(
          annotation_type: 'payment_processed',
          content: {
            payment_id: payment_results['payment_id'],
            amount_charged: payment_results['amount_charged'],
            processing_time_ms: calculate_step_duration(payment_step),
            payment_method_type: payment_results['payment_method_type']
          }
        )
      end

      # Track completion metrics
      if task.status == 'complete'
        total_duration = steps.sum { |s| calculate_step_duration(s) }
        task.annotations.create!(
          annotation_type: 'checkout_completed',
          content: {
            total_duration_ms: total_duration,
            steps_completed: steps.count,
            customer_email: task.context['customer_info']['email'],
            order_total: task.context.dig('payment_info', 'amount'),
            workflow_version: '1.0.0',
            environment: Rails.env
          }
        )
      end

      # Track failure analysis
      if task.status == 'error'
        failed_step = steps.find { |s| s.status == 'error' }
        if failed_step
          task.annotations.create!(
            annotation_type: 'checkout_failed',
            content: {
              failed_step: failed_step.name,
              attempts: failed_step.attempts,
              customer_email: task.context['customer_info']['email']
            }
          )
        end
      end
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
