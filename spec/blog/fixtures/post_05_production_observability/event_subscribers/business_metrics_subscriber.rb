# frozen_string_literal: true

# NOTE: BaseSubscriber will be loaded by the test environment

module BlogExamples
  module Post05
    module EventSubscribers
      # Subscriber that tracks business metrics from workflow events
      class BusinessMetricsSubscriber < Tasker::Events::Subscribers::BaseSubscriber
        # Subscribe to events we care about
        subscribe_to 'task.completed', 'task.failed', 'step.completed', 'step.failed'

        def initialize(*args, **kwargs)
          super
          # Initialize observability services
          @metrics_service = MockMetricsService.new
          @error_reporter = MockErrorReportingService.new
        end

        # Track checkout workflow completion for conversion metrics
        def handle_task_completed(event)
          return unless safe_get(event, :task_name) == 'monitored_checkout'
          return unless safe_get(event, :namespace_name) == 'blog_examples'

          # Extract business context from task
          context = safe_get(event, :context, {})

          # Track successful checkout conversion
          track_checkout_conversion(event)

          # Track revenue metrics
          track_revenue_metrics(context[:order_value], context[:customer_tier]) if context[:order_value]

          # Log for observability
          Rails.logger.info(
            message: 'Checkout completed successfully',
            event_type: 'business.checkout.completed',
            task_id: safe_get(event, :task_id),
            order_value: context[:order_value],
            customer_tier: context[:customer_tier],
            execution_time_seconds: safe_get(event, :execution_duration_seconds),
            correlation_id: safe_get(event, :correlation_id)
          )
        end

        # Track checkout workflow failures for conversion impact
        def handle_task_failed(event)
          return unless safe_get(event, :task_name) == 'monitored_checkout'
          return unless safe_get(event, :namespace_name) == 'blog_examples'

          context = safe_get(event, :context, {})

          # Track failed checkout
          track_checkout_failure(event)

          # Calculate revenue impact
          track_revenue_loss(context[:order_value], context[:customer_tier]) if context[:order_value]

          # Log critical business impact
          Rails.logger.error(
            message: 'Checkout failed - revenue impact',
            event_type: 'business.checkout.failed',
            task_id: safe_get(event, :task_id),
            order_value: context[:order_value],
            customer_tier: context[:customer_tier],
            error_message: safe_get(event, :error_message),
            failed_step: safe_get(event, :failed_step_name),
            revenue_impact: context[:order_value] || 0,
            correlation_id: safe_get(event, :correlation_id)
          )
        end

        # Track individual step performance for bottleneck identification
        def handle_step_completed(event)
          return unless safe_get(event, :task_namespace) == 'blog_examples'

          step_name = safe_get(event, :step_name)
          execution_time = safe_get(event, :execution_duration_seconds)

          # Track step-level metrics
          track_step_performance(step_name, execution_time)

          # Identify bottlenecks
          threshold = bottleneck_threshold_for(step_name)
          if execution_time > threshold
            Rails.logger.warn(
              message: 'Step performance degradation detected',
              event_type: 'business.performance.bottleneck',
              step_name: step_name,
              execution_time_seconds: execution_time,
              threshold_seconds: threshold,
              task_id: safe_get(event, :task_id),
              correlation_id: safe_get(event, :correlation_id)
            )

            # Report performance bottleneck
            @error_reporter.capture_message(
              "Performance bottleneck: #{step_name}",
              context: {
                step_name: step_name,
                execution_time: execution_time,
                threshold: threshold,
                degradation_factor: (execution_time / threshold).round(2)
              },
              level: 'warning'
            )
          end

          # Track payment-specific metrics
          return unless step_name == 'process_payment'

          results = safe_get(event, :results, {})

          return unless results[:payment_successful]

          track_payment_metrics(
            amount: results[:amount],
            payment_method: results[:payment_method],
            processing_time: execution_time
          )
        end

        # Track inventory impact
        def handle_step_failed(event)
          return unless safe_get(event, :step_name) == 'update_inventory'

          Rails.logger.error(
            message: 'Inventory update failed - potential oversell risk',
            event_type: 'business.inventory.failure',
            task_id: safe_get(event, :task_id),
            error_message: safe_get(event, :error_message),
            correlation_id: safe_get(event, :correlation_id)
          )

          # Report critical inventory failure
          @error_reporter.capture_message(
            'Critical: Inventory update failed - oversell risk',
            context: {
              task_id: safe_get(event, :task_id),
              error_message: safe_get(event, :error_message),
              step_name: safe_get(event, :step_name)
            },
            tags: {
              critical_failure: true,
              business_impact: 'inventory_oversell_risk'
            },
            level: 'error'
          )
        end

        private

        def track_checkout_conversion(event)
          # In a real implementation, this would update metrics storage
          @metrics_service.counter(
            'checkout_conversions_total',
            namespace: safe_get(event, :namespace_name),
            version: safe_get(event, :task_version)
          )

          # Add breadcrumb for successful conversion
          @error_reporter.add_breadcrumb(
            'Checkout conversion successful',
            category: 'business',
            data: {
              task_id: safe_get(event, :task_id),
              namespace: safe_get(event, :namespace_name)
            }
          )
        end

        def track_checkout_failure(event)
          error_type = classify_error(safe_get(event, :error_message))

          @metrics_service.counter(
            'checkout_failures_total',
            namespace: safe_get(event, :namespace_name),
            failed_step: safe_get(event, :failed_step_name),
            error_type: error_type
          )

          # Report checkout failure as error
          @error_reporter.capture_message(
            "Checkout failure: #{error_type}",
            context: {
              task_id: safe_get(event, :task_id),
              failed_step: safe_get(event, :failed_step_name),
              error_message: safe_get(event, :error_message),
              namespace: safe_get(event, :namespace_name)
            },
            tags: {
              error_type: error_type,
              business_impact: 'checkout_failure'
            },
            level: 'error'
          )
        end

        def track_revenue_metrics(order_value, customer_tier)
          @metrics_service.counter(
            'revenue_processed',
            value: order_value,
            customer_tier: customer_tier || 'standard'
          )

          # Track high-value orders
          return unless order_value > 1000

          @error_reporter.add_breadcrumb(
            "High-value order processed: $#{order_value}",
            category: 'business',
            data: {
              order_value: order_value,
              customer_tier: customer_tier
            }
          )
        end

        def track_revenue_loss(order_value, customer_tier)
          @metrics_service.counter(
            'revenue_loss',
            value: order_value,
            customer_tier: customer_tier || 'standard'
          )

          # Report significant revenue loss
          return unless order_value > 500

          @error_reporter.capture_message(
            "Significant revenue loss: $#{order_value}",
            context: {
              order_value: order_value,
              customer_tier: customer_tier || 'standard'
            },
            level: 'error'
          )
        end

        def track_step_performance(step_name, execution_time)
          @metrics_service.histogram(
            'step_execution_duration_seconds',
            value: execution_time,
            step_name: step_name,
            namespace: 'blog_examples'
          )
        end

        def track_payment_metrics(amount:, payment_method:, processing_time:)
          @metrics_service.counter(
            'payments_processed_total',
            payment_method: payment_method
          )

          @metrics_service.counter(
            'payment_volume',
            value: amount,
            payment_method: payment_method
          )

          @metrics_service.histogram(
            'payment_processing_duration_seconds',
            value: processing_time,
            payment_method: payment_method
          )

          # Add breadcrumb for payment processing
          @error_reporter.add_breadcrumb(
            "Payment processed: #{payment_method}",
            category: 'payment',
            data: {
              amount: amount,
              payment_method: payment_method,
              processing_time: processing_time
            }
          )
        end

        def bottleneck_threshold_for(step_name)
          thresholds = {
            'validate_cart' => 2.0,
            'process_payment' => 5.0,
            'update_inventory' => 3.0,
            'create_order' => 2.0,
            'send_confirmation' => 4.0
          }
          thresholds[step_name] || 5.0
        end

        def classify_error(error_message)
          return 'unknown' if error_message.nil?

          case error_message
          when /timeout/i
            'timeout'
          when /connection/i
            'connection'
          when /validation/i
            'validation'
          when /payment/i
            'payment'
          when /inventory/i
            'inventory'
          else
            'other'
          end
        end
      end
    end
  end
end
