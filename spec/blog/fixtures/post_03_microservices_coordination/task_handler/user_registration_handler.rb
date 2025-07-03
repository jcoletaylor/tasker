# frozen_string_literal: true

module BlogExamples
  module Post03
    # UserRegistrationHandler demonstrates YAML-driven task configuration
    # This example shows the ConfiguredTask pattern using manual YAML loading
    # for compatibility with the blog test framework
    #
    # NOTE: In production, you would use:
    #   class UserRegistrationHandler < Tasker::ConfiguredTask
    # The framework automatically handles YAML loading and registration
    class UserRegistrationHandler
      include Tasker::TaskHandler

      def initialize
        # Load YAML configuration manually (demonstrates ConfiguredTask pattern)
        yaml_path = File.expand_path('../config/user_registration_handler.yaml', __dir__)
        @config = YAML.load_file(yaml_path)

        # Define step templates from YAML (normally done automatically by ConfiguredTask)
        define_step_templates_from_config
      end

      # Business logic for step configuration (optional)
      def get_step_config(task, step_name)
        case step_name
        when 'create_user_account'
          {
            user_info: task.context['user_info'],
            service_url: 'https://api.userservice.com'
          }
        when 'setup_billing_profile'
          {
            billing_info: task.context['billing_info'],
            service_url: 'https://api.billingservice.com'
          }
        when 'initialize_preferences'
          {
            preferences: task.context['preferences'],
            service_url: 'https://api.preferencesservice.com'
          }
        else
          {}
        end
      end

      # Validate task context before execution
      # @param task [Tasker::Task] The task to validate
      # @return [Boolean] True if valid
      # @raise [ArgumentError] If validation fails
      def validate_context(task)
        context = task.context

        # Validate required email
        raise ArgumentError, 'email is required for user registration' unless context['email']

        # Basic email format validation
        unless context['email'].match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
          raise ArgumentError, 'email must be a valid email address'
        end

        # Validate optional plan
        if context['plan']
          valid_plans = %w[free basic premium enterprise]
          unless valid_plans.include?(context['plan'])
            raise ArgumentError, "plan must be one of: #{valid_plans.join(', ')}"
          end
        end

        # Validate optional source
        if context['source']
          valid_sources = %w[web mobile api admin]
          unless valid_sources.include?(context['source'])
            raise ArgumentError, "source must be one of: #{valid_sources.join(', ')}"
          end
        end

        true
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

      def peak_registration_hours?
        hour = Time.current.hour
        # Peak hours: 9am-12pm and 7pm-10pm
        (9..11).cover?(hour) || (19..21).cover?(hour)
      end

      def disposable_email?(email)
        # Simple check - in production, use a comprehensive list
        domain = email.split('@').last
        disposable_domains = ['tempmail.com', 'throwaway.email', 'guerrillamail.com']
        disposable_domains.include?(domain)
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

      # Define step templates from YAML configuration using the framework's define_step_templates method
      # This simulates what ConfiguredTask does automatically
      def define_step_templates_from_config
        step_templates = @config['step_templates'] || []
        default_system = @config['default_dependent_system']

        # Use the framework's define_step_templates method with a block
        self.class.define_step_templates do |definer|
          step_templates.each do |template|
            # Resolve handler class from string name
            handler_class = Object.const_get(template['handler_class'])

            # Define the step template using the definer
            definer.define(
              dependent_system: template['dependent_system'] || default_system,
              name: template['name'],
              description: template['description'] || template['name'],
              default_retryable: template.fetch('default_retryable', true),
              default_retry_limit: template.fetch('default_retry_limit', 3),
              skippable: template.fetch('skippable', false),
              handler_class: handler_class,
              depends_on_step: template['depends_on_step'],
              depends_on_steps: template['depends_on_steps'] || [],
              handler_config: template['handler_config']
            )
          end
        end
      end
    end
  end
end
