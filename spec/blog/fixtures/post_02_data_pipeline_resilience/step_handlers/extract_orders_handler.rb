module DataPipeline
  module StepHandlers
    class ExtractOrdersHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        date_range = task.context['date_range']
        start_date = Date.parse(date_range['start_date'])
        end_date = Date.parse(date_range['end_date'])
        force_refresh = task.context['force_refresh'] || false

        # Fire custom event for monitoring (handled by event subscribers)
        publish_event('data_extraction_started', {
          step_name: 'extract_orders',
          date_range: date_range,
          estimated_records: estimate_record_count(start_date, end_date),
          task_id: task.id
        })

        # Check cache first unless force refresh
        cached_data = get_cached_extraction('orders', start_date, end_date)
        if cached_data && !force_refresh
          log_structured_info("Using cached order data", {
            cache_key: cache_key('orders', start_date, end_date),
            records_count: cached_data['total_count']
          })
          return cached_data
        end

        # Calculate total records for progress tracking
        total_count = Order.where(created_at: start_date..end_date).count
        processed_count = 0
        orders = []

        log_structured_info("Starting order extraction", {
          total_records: total_count,
          date_range: date_range,
          batch_size: batch_size
        })

        # Process in batches to avoid memory issues
        Order.where(created_at: start_date..end_date)
             .includes(:order_items, :customer)
             .find_in_batches(batch_size: batch_size) do |batch|
          begin
            batch_data = batch.map do |order|
              {
                order_id: order.id,
                customer_id: order.customer_id,
                customer_email: order.customer&.email,
                total_amount: order.total_amount,
                subtotal: order.subtotal,
                tax_amount: order.tax_amount,
                shipping_amount: order.shipping_amount,
                order_date: order.created_at.iso8601,
                status: order.status,
                payment_method: order.payment_method,
                items: order.order_items.map { |item|
                  {
                    product_id: item.product_id,
                    quantity: item.quantity,
                    unit_price: item.unit_price,
                    line_total: item.line_total,
                    category: item.product&.category
                  }
                }
              }
            end

            orders.concat(batch_data)
            processed_count += batch.size

            # Update progress annotation for monitoring
            update_progress(step, processed_count, total_count)

            # Yield control periodically to avoid blocking
            sleep(0.1) if processed_count % 5000 == 0

          rescue ActiveRecord::ConnectionTimeoutError => e
            # Log the error but let Tasker handle retries
            log_structured_error("Database connection timeout during order extraction", {
              error: e.message,
              batch_size: batch.size,
              processed_so_far: processed_count,
              total_expected: total_count
            })
            raise e  # Let Tasker retry with backoff
          rescue ActiveRecord::StatementInvalid => e
            log_structured_error("Database query error during order extraction", {
              error: e.message,
              batch_size: batch.size,
              processed_so_far: processed_count
            })
            raise e  # Let Tasker handle retries
          rescue StandardError => e
            log_structured_error("Order extraction error", {
              error: e.message,
              error_class: e.class.name,
              batch_size: batch.size,
              processed_so_far: processed_count
            })
            raise e  # Let Tasker handle retries
          end
        end

        # Calculate data quality metrics
        data_quality = calculate_data_quality(orders)

        result = {
          orders: orders,
          total_count: orders.length,
          date_range: {
            start_date: start_date.iso8601,
            end_date: end_date.iso8601
          },
          extracted_at: Time.current.iso8601,
          data_quality: data_quality,
          processing_stats: {
            batches_processed: (processed_count.to_f / batch_size).ceil,
            batch_size: batch_size,
            processing_time_seconds: calculate_duration_seconds(step)
          }
        }

        # Cache the result
        cache_extraction('orders', start_date, end_date, result)

        log_structured_info("Order extraction completed successfully", {
          records_extracted: orders.length,
          processing_time_seconds: calculate_duration_seconds(step),
          data_quality_score: data_quality[:quality_score]
        })

        # Fire completion event with metrics (handled by event subscribers)
        publish_event('data_extraction_completed', {
          step_name: 'extract_orders',
          records_extracted: orders.length,
          processing_time_seconds: calculate_duration_seconds(step),
          data_quality: data_quality,
          date_range: date_range,
          task_id: task.id
        })

        result
      end

      private

      def batch_size
        # Adjust batch size based on memory profile annotation
        base_size = 1000
        multiplier = get_task_annotation('batch_size_multiplier')&.to_f || 1.0
        (base_size * multiplier).to_i
      end

      def estimate_record_count(start_date, end_date)
        # Quick estimate without full count for monitoring
        sample_day = Order.where(created_at: start_date..start_date.end_of_day).count
        days_span = (end_date - start_date).to_i + 1
        sample_day * days_span
      end

      def update_progress(step, processed, total)
        progress_percent = (processed.to_f / total * 100).round(1)
        step.annotations.merge!({
          progress_message: "Processed #{processed}/#{total} orders (#{progress_percent}%)",
          progress_percent: progress_percent,
          last_updated: Time.current.iso8601
        })
        step.save!
      end

      def calculate_data_quality(orders)
        return { quality_score: 0 } if orders.empty?

        records_with_items = orders.count { |o| o[:items].any? }
        records_with_email = orders.count { |o| o[:customer_email].present? }
        records_with_valid_amounts = orders.count { |o| o[:total_amount] > 0 }

        quality_score = [
          (records_with_items.to_f / orders.length * 100).round(1),
          (records_with_email.to_f / orders.length * 100).round(1),
          (records_with_valid_amounts.to_f / orders.length * 100).round(1)
        ].sum / 3.0

        {
          quality_score: quality_score.round(1),
          records_with_items: records_with_items,
          records_with_email: records_with_email,
          records_with_valid_amounts: records_with_valid_amounts,
          avg_order_value: orders.sum { |o| o[:total_amount] } / orders.length.to_f,
          unique_customers: orders.map { |o| o[:customer_id] }.uniq.length,
          date_range_coverage: orders.length > 0 ? 100.0 : 0.0
        }
      end

      def cache_key(data_type, start_date, end_date)
        "extraction:#{data_type}:#{start_date}:#{end_date}"
      end

      def get_cached_extraction(data_type, start_date, end_date)
        Rails.cache.read(cache_key(data_type, start_date, end_date))
      end

      def cache_extraction(data_type, start_date, end_date, data)
        Rails.cache.write(cache_key(data_type, start_date, end_date), data, expires_in: 6.hours)
      end

      def log_structured_info(message, **context)
        log_structured(:info, message, step_name: 'extract_orders', **context)
      end

      def log_structured_error(message, **context)
        log_structured(:error, message, step_name: 'extract_orders', **context)
      end

      def calculate_duration_seconds(step)
        return 0 unless step.started_at.present?
        end_time = step.completed_at || Time.current
        (end_time - step.started_at).to_i
      end

      def get_task_annotation(key)
        # Access task annotations through the sequence's task
        sequence = step.sequence
        task = sequence&.task
        task&.annotations&.dig(key)
      end
    end
  end
end
