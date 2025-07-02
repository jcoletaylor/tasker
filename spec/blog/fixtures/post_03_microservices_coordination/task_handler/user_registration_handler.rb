module UserManagement
  class UserRegistrationHandler < Tasker::ConfiguredTask

    # Runtime step dependency and configuration customization
    def establish_step_dependencies_and_defaults(task, steps)
      # Generate correlation ID if not provided
      correlation_id = task.context['correlation_id'] || generate_correlation_id
      task.annotations['correlation_id'] = correlation_id
      
      # Track registration source for analytics
      task.annotations['registration_source'] = task.context['source'] || 'web'
      task.annotations['plan_type'] = task.context['plan'] || 'free'
      
      # Service-specific timeouts based on plan
      if task.context['plan'] == 'enterprise'
        # Enterprise gets more retries and longer timeouts
        account_step = steps.find { |s| s.name == 'create_user_account' }
        billing_step = steps.find { |s| s.name == 'setup_billing_profile' }
        
        if account_step
          account_step.retry_limit = 5
          account_step.handler_config = account_step.handler_config.merge(timeout_seconds: 45)
        end
        
        if billing_step
          billing_step.retry_limit = 5
          billing_step.handler_config = billing_step.handler_config.merge(timeout_seconds: 45)
        end
      end
      
      # Peak hours handling
      if peak_registration_hours?
        welcome_step = steps.find { |s| s.name == 'send_welcome_sequence' }
        if welcome_step
          welcome_step.handler_config = welcome_step.handler_config.merge(
            timeout_seconds: 30,
            backoff_request_seconds: 60  # Rate limiting protection
          )
        end
      end
      
      # Add monitoring annotations to all steps
      steps.each do |step|
        step.annotations['correlation_id'] = correlation_id
        step.annotations['workflow_type'] = 'user_registration'
        step.annotations['plan_type'] = task.context['plan'] || 'free'
      end
      
      # Add task-level annotations
      task.annotations['workflow_type'] = 'user_registration'
      task.annotations['environment'] = Rails.env
      task.annotations['initiated_at'] = Time.current.iso8601
    end

    # Custom validation for registration
    def validate_context(context)
      errors = super(context)
      
      # Email validation
      if context['email']
        unless context['email'].match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
          errors << "Email format is invalid"
        end
        
        # Check for disposable email domains
        if disposable_email?(context['email'])
          errors << "Disposable email addresses are not allowed"
        end
      end
      
      # Phone validation if provided
      if context['phone'].present?
        unless context['phone'].match?(/\A\+?[\d\s\-\(\)]+\z/)
          errors << "Phone number format is invalid"
        end
      end
      
      # Enterprise plan requirements
      if context['plan'] == 'enterprise' && context['company_name'].blank?
        errors << "Company name is required for enterprise plans"
      end
      
      errors
    end

    # Post-completion hooks
    def update_annotations(task, sequence, steps)
      # Record service response times
      service_timings = {}
      steps.each do |step|
        if step.results && step.results['service_response_time']
          service_name = step.annotations['service'] || 'unknown'
          service_timings[service_name] = step.results['service_response_time']
        end
      end
      
      task.annotations.create!(
        annotation_type: 'service_performance',
        content: {
          service_timings: service_timings,
          total_duration: calculate_total_duration(steps),
          parallel_execution_saved: calculate_parallel_savings(steps)
        }
      )
      
      # Record registration outcome
      task.annotations.create!(
        annotation_type: 'registration_outcome',
        content: {
          user_id: steps.find { |s| s.name == 'create_user_account' }&.results&.dig('user_id'),
          plan: task.context['plan'],
          source: task.context['source'],
          completed_at: Time.current.iso8601
        }
      )
    end

    private

    def generate_correlation_id
      "reg_#{Time.current.to_i}_#{SecureRandom.hex(4)}"
    end

    def peak_registration_hours?
      hour = Time.current.hour
      # Peak hours: 9am-12pm and 7pm-10pm
      (9..11).include?(hour) || (19..21).include?(hour)
    end

    def disposable_email?(email)
      # Simple check - in production, use a comprehensive list
      domain = email.split('@').last
      disposable_domains = ['tempmail.com', 'throwaway.email', 'guerrillamail.com']
      disposable_domains.include?(domain)
    end

    def calculate_total_duration(steps)
      return 0 if steps.empty?
      
      start_time = steps.map(&:started_at).compact.min
      end_time = steps.map(&:completed_at).compact.max
      
      return 0 unless start_time && end_time
      ((end_time - start_time) * 1000).to_i  # milliseconds
    end

    def calculate_parallel_savings(steps)
      # Calculate how much time was saved by parallel execution
      sequential_time = steps.sum { |s| calculate_step_duration(s) }
      actual_time = calculate_total_duration(steps)
      
      sequential_time - actual_time
    end

    def calculate_step_duration(step)
      return 0 unless step.started_at && step.completed_at
      ((step.completed_at - step.started_at) * 1000).to_i
    end
  end
end