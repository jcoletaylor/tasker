# frozen_string_literal: true

# Note: BaseSubscriber will be loaded by the test environment

module BlogExamples
  module Post05
    module EventSubscribers
      # Subscriber that monitors system performance and health metrics
      class PerformanceMonitoringSubscriber < Tasker::Events::Subscribers::BaseSubscriber
        # Subscribe to performance-related events
        subscribe_to 'task.completed', 'task.failed', 'step.completed', 'step.failed'
        
        def initialize(*args, **kwargs)
          super
          # Initialize observability services
          @metrics_service = MockMetricsService.new
          @error_reporter = MockErrorReportingService.new
        end

        # Track overall task execution performance
        def handle_task_completed(event)
          execution_time = safe_get(event, :execution_duration_seconds)
          namespace = safe_get(event, :namespace_name)
          task_name = safe_get(event, :task_name)
          
          # Track task completion metrics
          @metrics_service.histogram(
            'task_execution_duration_seconds',
            value: execution_time,
            namespace: namespace,
            task_name: task_name
          )
          
          # Track namespace-level performance
          track_namespace_performance(namespace, execution_time)
          
          # Monitor SLA compliance
          check_sla_compliance(event)
        end

        # Monitor step execution patterns
        def handle_step_completed(event)
          step_name = safe_get(event, :step_name)
          execution_time = safe_get(event, :execution_duration_seconds)
          retry_count = safe_get(event, :retry_count, 0)
          
          # Track step performance
          @metrics_service.histogram(
            'step_execution_duration_seconds',
            value: execution_time,
            step_name: step_name,
            namespace: safe_get(event, :task_namespace),
            retry_count: retry_count
          )
          
          # Monitor retry patterns
          if retry_count > 0
            @metrics_service.counter(
              'step_retries_total',
              step_name: step_name,
              namespace: safe_get(event, :task_namespace)
            )
          end
        end

        # Track failed executions for error rate monitoring
        def handle_task_failed(event)
          namespace = safe_get(event, :namespace_name)
          task_name = safe_get(event, :task_name)
          error_type = classify_error(safe_get(event, :error_message))
          
          # Track failure metrics
          @metrics_service.counter(
            'task_failures_total',
            namespace: namespace,
            task_name: task_name,
            error_type: error_type
          )
          
          # Report critical errors
          if error_type == 'timeout' || error_type == 'connection'
            @error_reporter.capture_message(
              "Critical task failure: #{error_type}",
              context: {
                namespace: namespace,
                task_name: task_name,
                task_id: safe_get(event, :task_id)
              },
              tags: { error_type: error_type },
              level: 'error'
            )
          end
          
          # Calculate and track error rates
          update_error_rate_metrics(namespace, task_name)
        end

        # Monitor step-level failures
        def handle_step_failed(event)
          step_name = safe_get(event, :step_name)
          error_message = safe_get(event, :error_message)
          retry_count = safe_get(event, :retry_count, 0)
          
          # Track step failure patterns
          @metrics_service.counter(
            'step_failures_total',
            step_name: step_name,
            namespace: safe_get(event, :task_namespace),
            error_type: classify_error(error_message),
            final_failure: safe_get(event, :max_retries_reached, false)
          )
          
          # Monitor retry exhaustion
          if safe_get(event, :max_retries_reached)
            Rails.logger.error(
              message: "Step exhausted all retries",
              event_type: "performance.step.retry_exhausted",
              step_name: step_name,
              retry_count: retry_count,
              task_id: safe_get(event, :task_id)
            )
            
            # Report retry exhaustion to error tracking
            @error_reporter.capture_message(
              "Step retry exhaustion: #{step_name}",
              context: {
                step_name: step_name,
                retry_count: retry_count,
                task_id: safe_get(event, :task_id),
                error_message: error_message
              },
              level: 'error'
            )
          end
        end

        private

        def track_namespace_performance(namespace, execution_time)
          # Track rolling performance metrics by namespace
          @metrics_service.gauge(
            'namespace_avg_execution_seconds',
            value: calculate_rolling_average(namespace, execution_time),
            namespace: namespace
          )
        end

        def check_sla_compliance(event)
          # Check if task met its SLA
          handler_config = safe_get(event, :handler_config, {})
          sla_seconds = handler_config.dig('monitoring', 'sla_seconds')
          
          return unless sla_seconds
          
          execution_time = safe_get(event, :execution_duration_seconds)
          sla_met = execution_time <= sla_seconds
          
          @metrics_service.counter(
            'sla_compliance_total',
            namespace: safe_get(event, :namespace_name),
            task_name: safe_get(event, :task_name),
            sla_met: sla_met
          )
          
          unless sla_met
            Rails.logger.warn(
              message: "SLA violation detected",
              event_type: "performance.sla.violation",
              task_id: safe_get(event, :task_id),
              execution_time_seconds: execution_time,
              sla_seconds: sla_seconds,
              violation_seconds: execution_time - sla_seconds
            )
            
            # Report SLA violations
            @error_reporter.capture_message(
              "SLA violation: #{safe_get(event, :task_name)}",
              context: {
                task_id: safe_get(event, :task_id),
                execution_time: execution_time,
                sla_seconds: sla_seconds,
                violation_seconds: execution_time - sla_seconds
              },
              tags: {
                namespace: safe_get(event, :namespace_name),
                task_name: safe_get(event, :task_name)
              },
              level: 'warning'
            )
          end
        end

        def update_error_rate_metrics(namespace, task_name)
          # Calculate error rate over sliding window
          # In a real implementation, this would use a time-series database
          error_rate = calculate_error_rate(namespace, task_name)
          
          @metrics_service.gauge(
            'task_error_rate_percent',
            value: error_rate,
            namespace: namespace,
            task_name: task_name
          )
          
          # Alert on high error rates
          if error_rate > 10.0
            @error_reporter.capture_message(
              "High error rate detected: #{error_rate}%",
              context: {
                namespace: namespace,
                task_name: task_name,
                error_rate: error_rate
              },
              level: 'error'
            )
          end
        end

        def classify_error(error_message)
          return 'unknown' if error_message.nil?
          
          case error_message
          when /timeout/i
            'timeout'
          when /connection/i
            'connection'
          when /memory/i
            'resource'
          when /retry/i
            'retry_exhausted'
          else
            'application'
          end
        end

        def calculate_rolling_average(namespace, new_value)
          # Calculate rolling average for namespace
          # In a real implementation, this would maintain a sliding window
          new_value * 0.9 + rand(5)
        end

        def calculate_error_rate(namespace, task_name)
          # Calculate error rate percentage
          # In a real implementation, this would query metrics storage
          rand(0.1..5.0).round(2)
        end
      end
    end
  end
end