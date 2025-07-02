module DataPipeline
  module StepHandlers
    class TransformCustomerMetricsHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        orders_data = step_results(sequence, 'extract_orders')
        users_data = step_results(sequence, 'extract_users')

        orders = orders_data['orders'] || []
        users = users_data['users'] || []

        log_structured_info("Starting customer metrics transformation", {
          orders_count: orders.length,
          users_count: users.length
        })

        # Validate we have the required data
        if orders.empty?
          log_structured_error("No orders data available for transformation", {
            orders_data_keys: orders_data.keys,
            users_data_keys: users_data.keys
          })
          raise StandardError, "Cannot calculate customer metrics without order data"
        end

        if users.empty?
          log_structured_error("No users data available for transformation", {
            orders_data_keys: orders_data.keys,
            users_data_keys: users_data.keys
          })
          raise StandardError, "Cannot calculate customer metrics without user data"
        end

        # Create lookup hash for efficient user data access
        users_by_id = users.index_by { |user| user['user_id'] }

        # Group orders by customer
        orders_by_customer = orders.group_by { |order| order['customer_id'] }

        customer_metrics = []
        processed_customers = 0
        total_customers = orders_by_customer.keys.length
        skipped_customers = 0

        log_structured_info("Processing customer metrics", {
          total_customers: total_customers,
          batch_processing: true
        })

        orders_by_customer.each do |customer_id, customer_orders|
          user_info = users_by_id[customer_id]

          unless user_info
            skipped_customers += 1
            next  # Skip if user data missing
          end

          begin
            metrics = calculate_customer_metrics(customer_orders, user_info)
            customer_metrics << metrics
            processed_customers += 1

            # Update progress every 100 customers
            if processed_customers % 100 == 0
              update_progress(step, processed_customers, total_customers)
            end

          rescue StandardError => e
            log_structured_error("Error calculating metrics for customer", {
              customer_id: customer_id,
              error: e.message,
              error_class: e.class.name,
              orders_count: customer_orders.length
            })
            # Continue processing other customers rather than failing entirely
            skipped_customers += 1
          end
        end

        # Final progress update
        update_progress(step, processed_customers, total_customers)

        # Calculate quality metrics
        quality_metrics = {
          customers_processed: processed_customers,
          customers_skipped: skipped_customers,
          processing_success_rate: (processed_customers.to_f / total_customers * 100).round(2),
          data_completeness_score: calculate_data_completeness(customer_metrics)
        }

        result = {
          customer_metrics: customer_metrics,
          total_customers: customer_metrics.length,
          processing_stats: {
            customers_processed: processed_customers,
            customers_skipped: skipped_customers,
            total_customers_in_orders: total_customers,
            processing_time_seconds: step.duration_seconds
          },
          metrics_calculated: %w[
            total_lifetime_value
            average_order_value
            order_frequency
            days_since_last_order
            customer_segment
            acquisition_cohort
            recency_score
          ],
          quality_metrics: quality_metrics,
          calculated_at: Time.current.iso8601
        }

        log_structured_info("Customer metrics transformation completed", {
          customers_processed: processed_customers,
          customers_skipped: skipped_customers,
          success_rate: quality_metrics[:processing_success_rate],
          processing_time_seconds: step.duration_seconds
        })

        result
      end

      private

      def step_results(sequence, step_name)
        step = sequence.steps.find { |s| s.name == step_name }
        step&.results || {}
      end

      def calculate_customer_metrics(customer_orders, user_info)
        total_spent = customer_orders.sum { |order| order['total_amount'] || 0 }
        order_count = customer_orders.length
        avg_order_value = order_count > 0 ? total_spent / order_count : 0

        # Parse order dates safely
        order_dates = customer_orders.filter_map do |order|
          Date.parse(order['order_date']) rescue nil
        end.sort

        last_order_date = order_dates.last
        first_order_date = order_dates.first
        days_since_last_order = last_order_date ? (Date.current - last_order_date).to_i : nil

        {
          customer_id: user_info['user_id'],
          customer_email: user_info['email'],
          total_lifetime_value: total_spent.round(2),
          average_order_value: avg_order_value.round(2),
          total_orders: order_count,
          order_frequency: calculate_order_frequency(order_dates),
          days_since_last_order: days_since_last_order,
          customer_segment: determine_customer_segment(total_spent, order_count),
          acquisition_date: user_info['created_at'],
          acquisition_cohort: determine_acquisition_cohort(user_info['created_at']),
          recency_score: calculate_recency_score(days_since_last_order),
          order_date_range: {
            first_order: first_order_date&.iso8601,
            last_order: last_order_date&.iso8601,
            span_days: first_order_date && last_order_date ? (last_order_date - first_order_date).to_i : 0
          },
          calculated_at: Time.current.iso8601
        }
      end

      def calculate_order_frequency(order_dates)
        return 0 if order_dates.length < 2

        total_days = order_dates.last - order_dates.first
        return 0 if total_days <= 0

        # Orders per month
        ((order_dates.length - 1) / (total_days / 30.0)).round(2)
      end

      def determine_customer_segment(total_spent, order_count)
        case
        when total_spent >= 1000 && order_count >= 10
          'VIP'
        when total_spent >= 500 || order_count >= 5
          'Regular'
        when total_spent >= 100 || order_count >= 2
          'Occasional'
        else
          'New'
        end
      end

      def determine_acquisition_cohort(created_at_string)
        return 'Unknown' unless created_at_string

        begin
          created_date = Date.parse(created_at_string)
          "#{created_date.year}-Q#{((created_date.month - 1) / 3) + 1}"
        rescue
          'Unknown'
        end
      end

      def calculate_recency_score(days_since_last_order)
        return 0 unless days_since_last_order

        case days_since_last_order
        when 0..30
          5  # Very recent
        when 31..90
          4  # Recent
        when 91..180
          3  # Moderate
        when 181..365
          2  # Old
        else
          1  # Very old
        end
      end

      def calculate_data_completeness(customer_metrics)
        return 0 if customer_metrics.empty?

        total_fields = customer_metrics.length * 5  # 5 key fields to check
        complete_fields = 0

        customer_metrics.each do |metrics|
          complete_fields += 1 if metrics[:customer_email].present?
          complete_fields += 1 if metrics[:total_lifetime_value] > 0
          complete_fields += 1 if metrics[:total_orders] > 0
          complete_fields += 1 if metrics[:acquisition_date].present?
          complete_fields += 1 if metrics[:customer_segment] != 'Unknown'
        end

        (complete_fields.to_f / total_fields * 100).round(2)
      end

      def update_progress(step, processed, total)
        progress_percent = (processed.to_f / total * 100).round(1)
        step.annotations.merge!({
          progress_message: "Processed #{processed}/#{total} customers (#{progress_percent}%)",
          progress_percent: progress_percent,
          last_updated: Time.current.iso8601
        })
        step.save!
      end

      def log_structured_info(message, **context)
        log_structured(:info, message, step_name: 'transform_customer_metrics', **context)
      end

      def log_structured_error(message, **context)
        log_structured(:error, message, step_name: 'transform_customer_metrics', **context)
      end
    end
  end
end
