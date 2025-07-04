# frozen_string_literal: true

module BlogExamples
  module Post03
    # UserRegistrationHandler demonstrates YAML-driven task configuration
    # This example shows the ConfiguredTask pattern for modern Tasker applications
    class UserRegistrationHandler < Tasker::ConfiguredTask
      def self.yaml_path
        @yaml_path ||= File.join(
          File.dirname(__FILE__),
          '..', 'config', 'user_registration_handler.yaml'
        )
      end

      # Post-completion hooks
      def update_annotations(task, _sequence, steps)
        # Record service response times in task context (simplified for testing)
        service_timings = {}
        steps.each do |step|
          if step.results && step.results['service_response_time']
            service_name = step.name
            service_timings[service_name] = step.results['service_response_time']
          end
        end

        # Store in task context for testing
        task.context['service_performance'] = {
          service_timings: service_timings,
          total_duration: calculate_total_duration(steps),
          parallel_execution_saved: calculate_parallel_savings(steps)
        }

        # Record registration outcome
        task.context['registration_outcome'] = {
          user_id: steps.find { |s| s.name == 'create_user_account' }&.results&.dig('user_id'),
          plan: task.context['plan'],
          source: task.context['source'],
          completed_at: Time.current.iso8601
        }

        # Set fields expected by tests
        task.context['plan_type'] = task.context.dig('user_info', 'plan') || task.context['plan'] || 'free'
        task.context['correlation_id'] = task.context['correlation_id'] || generate_correlation_id
        task.context['registration_source'] = task.context.dig('user_info', 'source') || task.context['source'] || 'web'

        # Save the task to persist context changes
        task.save! if task.respond_to?(:save!)
      end

      private

      def generate_correlation_id
        "reg_#{Time.current.to_i}_#{SecureRandom.hex(4)}"
      end

      def calculate_total_duration(steps)
        return 0 unless steps.any?

        # Use created_at and updated_at since WorkflowStep doesn't have started_at
        start_time = steps.filter_map(&:created_at).min
        end_time = steps.filter_map(&:updated_at).max

        return 0 unless start_time && end_time

        ((end_time - start_time) * 1000).round(2) # Convert to milliseconds
      end

      def calculate_parallel_savings(steps)
        # Calculate how much time was saved by parallel execution
        sequential_time = steps.sum { |s| calculate_step_duration(s) }
        actual_time = calculate_total_duration(steps)

        sequential_time - actual_time
      end

      def calculate_step_duration(step)
        return 0 unless step.created_at && step.updated_at

        ((step.updated_at - step.created_at) * 1000).round(2) # Convert to milliseconds
      end
    end
  end
end
