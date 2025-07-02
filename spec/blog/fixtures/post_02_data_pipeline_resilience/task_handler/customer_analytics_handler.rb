module DataPipeline
  class CustomerAnalyticsHandler < Tasker::ConfiguredTask

    # Runtime step dependency and configuration customization
    def establish_step_dependencies_and_defaults(task, steps)
      date_range = task.context['date_range']
      start_date = Date.parse(date_range['start_date'])
      end_date = Date.parse(date_range['end_date'])
      days_span = (end_date - start_date).to_i + 1

      # Adjust timeouts and batch sizes based on date range
      if days_span > 30
        # Large date range - increase timeouts and enable distributed mode
        extract_orders_step = steps.find { |s| s.name == 'extract_orders' }
        extract_users_step = steps.find { |s| s.name == 'extract_users' }
        transform_customer_step = steps.find { |s| s.name == 'transform_customer_metrics' }
        transform_product_step = steps.find { |s| s.name == 'transform_product_metrics' }
        
        extract_orders_step&.handler_config&.merge!(timeout_seconds: 3600, max_retries: 5)
        extract_users_step&.handler_config&.merge!(timeout_seconds: 2400)
        transform_customer_step&.handler_config&.merge!(timeout_seconds: 5400)
        transform_product_step&.handler_config&.merge!(timeout_seconds: 3600)
      elsif days_span > 7
        # Medium date range - moderate adjustments
        extract_orders_step = steps.find { |s| s.name == 'extract_orders' }
        extract_users_step = steps.find { |s| s.name == 'extract_users' }
        
        extract_orders_step&.handler_config&.merge!(timeout_seconds: 2700)
        extract_users_step&.handler_config&.merge!(timeout_seconds: 1800)
      end

      # Processing mode optimizations
      case task.context['processing_mode']
      when 'high_memory'
        task.annotations['memory_profile'] = 'high_memory_optimized'
        task.annotations['batch_size_multiplier'] = '2.0'
        task.annotations['parallel_workers'] = '4'
      when 'distributed'
        task.annotations['processing_mode'] = 'distributed'
        task.annotations['worker_pool_size'] = '8'
        task.annotations['memory_limit'] = '4GB'
      else
        task.annotations['processing_mode'] = 'standard'
        task.annotations['batch_size_multiplier'] = '1.0'
      end

      # Quality thresholds as annotations for step handlers
      if task.context['quality_thresholds']
        task.context['quality_thresholds'].each do |key, value|
          task.annotations["quality_threshold_#{key}"] = value.to_s
        end
      end

      # Data pipeline specific annotations
      task.annotations['workflow_type'] = 'data_pipeline'
      task.annotations['pipeline_name'] = 'customer_analytics'
      task.annotations['data_version'] = '1.0.0'
      task.annotations['date_range_days'] = days_span.to_s
      task.annotations['environment'] = Rails.env
      task.annotations['force_refresh'] = task.context['force_refresh'].to_s
    end

    # Custom validation for data pipeline context
    def validate_context(context)
      errors = super(context)

      # Validate date range
      if context['date_range']
        start_date = Date.parse(context['date_range']['start_date']) rescue nil
        end_date = Date.parse(context['date_range']['end_date']) rescue nil

        if start_date && end_date
          if start_date > end_date
            errors << "start_date cannot be after end_date"
          end

          if start_date > Date.current
            errors << "start_date cannot be in the future"
          end

          days_span = (end_date - start_date).to_i + 1
          if days_span > 365
            errors << "date range cannot exceed 365 days"
          end
        end
      end

      # Validate processing mode constraints
      if context['processing_mode'] == 'distributed'
        unless Rails.env.production?
          errors << "distributed processing mode only available in production"
        end
      end

      errors
    end
  end
end
