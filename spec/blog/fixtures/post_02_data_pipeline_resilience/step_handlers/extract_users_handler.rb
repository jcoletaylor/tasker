module DataPipeline
  module StepHandlers
    class ExtractUsersHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        date_range = task.context['date_range']
        start_date = Date.parse(date_range['start_date'])
        end_date = Date.parse(date_range['end_date'])
        force_refresh = task.context['force_refresh'] || false

        # Fire custom event for monitoring
        publish_event('data_extraction_started', {
          step_name: 'extract_users',
          date_range: date_range,
          estimated_records: estimate_record_count(start_date, end_date),
          task_id: task.id
        })

        # Check cache first unless force refresh
        cached_data = get_cached_extraction('users', start_date, end_date)
        if cached_data && !force_refresh
          log_structured_info("Using cached user data", {
            cache_key: cache_key('users', start_date, end_date),
            records_count: cached_data['total_count']
          })
          return cached_data
        end

        log_structured_info("Starting user extraction", {
          date_range: date_range,
          force_refresh: force_refresh
        })

        # Extract users who had activity in the date range
        user_ids_from_orders = Order.where(created_at: start_date..end_date)
                                   .distinct
                                   .pluck(:customer_id)

        total_count = user_ids_from_orders.length
        processed_count = 0
        users = []

        log_structured_info("Processing user extraction", {
          user_ids_count: total_count,
          batch_size: batch_size
        })

        # Process in batches
        user_ids_from_orders.each_slice(batch_size) do |user_ids_batch|
          begin
            batch_users = User.where(id: user_ids_batch).includes(:profile)

            batch_data = batch_users.map do |user|
              {
                user_id: user.id,
                email: user.email,
                first_name: user.first_name,
                last_name: user.last_name,
                phone: user.phone,
                created_at: user.created_at.iso8601,
                updated_at: user.updated_at.iso8601,
                status: user.status,
                marketing_opt_in: user.marketing_opt_in,
                profile: user.profile ? {
                  age: user.profile.age,
                  gender: user.profile.gender,
                  location: {
                    city: user.profile.city,
                    state: user.profile.state,
                    country: user.profile.country,
                    zip_code: user.profile.zip_code
                  },
                  preferences: user.profile.preferences || {}
                } : nil
              }
            end

            users.concat(batch_data)
            processed_count += batch_data.length

            # Update progress
            update_progress(step, processed_count, total_count)

          rescue ActiveRecord::ConnectionTimeoutError => e
            log_structured_error("Database connection timeout during user extraction", {
              error: e.message,
              batch_size: user_ids_batch.size,
              processed_so_far: processed_count
            })
            raise e  # Let Tasker handle retries
          rescue StandardError => e
            log_structured_error("User extraction error", {
              error: e.message,
              error_class: e.class.name,
              batch_size: user_ids_batch.size,
              processed_so_far: processed_count
            })
            raise e  # Let Tasker handle retries
          end
        end

        # Calculate data quality metrics
        data_quality = calculate_data_quality(users)

        result = {
          users: users,
          total_count: users.length,
          date_range: {
            start_date: start_date.iso8601,
            end_date: end_date.iso8601
          },
          extracted_at: Time.current.iso8601,
          data_quality: data_quality,
          processing_stats: {
            batches_processed: (processed_count.to_f / batch_size).ceil,
            batch_size: batch_size,
            processing_time_seconds: step.duration_seconds
          }
        }

        # Cache the result
        cache_extraction('users', start_date, end_date, result)

        log_structured_info("User extraction completed successfully", {
          records_extracted: users.length,
          processing_time_seconds: step.duration_seconds,
          data_quality_score: data_quality[:quality_score]
        })

        # Fire completion event with metrics
        publish_event('data_extraction_completed', {
          step_name: 'extract_users',
          records_extracted: users.length,
          processing_time_seconds: step.duration_seconds,
          data_quality: data_quality,
          date_range: date_range,
          task_id: task.id
        })

        result
      end

      private

      def batch_size
        base_size = 500  # Smaller batches for user data with joins
        multiplier = task.annotations['batch_size_multiplier']&.to_f || 1.0
        (base_size * multiplier).to_i
      end

      def estimate_record_count(start_date, end_date)
        # Estimate based on order activity
        Order.where(created_at: start_date..end_date).distinct.count(:customer_id)
      end

      def update_progress(step, processed, total)
        progress_percent = (processed.to_f / total * 100).round(1)
        step.annotations.merge!({
          progress_message: "Processed #{processed}/#{total} users (#{progress_percent}%)",
          progress_percent: progress_percent,
          last_updated: Time.current.iso8601
        })
        step.save!
      end

      def calculate_data_quality(users)
        return { quality_score: 0 } if users.empty?

        users_with_email = users.count { |u| u[:email].present? }
        users_with_names = users.count { |u| u[:first_name].present? && u[:last_name].present? }
        users_with_profile = users.count { |u| u[:profile].present? }
        users_with_location = users.count { |u| u[:profile]&.dig(:location, :city).present? }

        quality_score = [
          (users_with_email.to_f / users.length * 100).round(1),
          (users_with_names.to_f / users.length * 100).round(1),
          (users_with_profile.to_f / users.length * 100).round(1),
          (users_with_location.to_f / users.length * 100).round(1)
        ].sum / 4.0

        {
          quality_score: quality_score.round(1),
          users_with_email: users_with_email,
          users_with_names: users_with_names,
          users_with_profile: users_with_profile,
          users_with_location: users_with_location,
          email_completeness: (users_with_email.to_f / users.length * 100).round(1),
          profile_completeness: (users_with_profile.to_f / users.length * 100).round(1)
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
        log_structured(:info, message, step_name: 'extract_users', **context)
      end

      def log_structured_error(message, **context)
        log_structured(:error, message, step_name: 'extract_users', **context)
      end
    end
  end
end
