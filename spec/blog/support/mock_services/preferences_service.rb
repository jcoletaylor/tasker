# frozen_string_literal: true

module BlogExamples
  module MockServices
    class MockPreferencesService < BaseMockService
      def initialize
        super
        @service_name = 'preferences_service'
        @preferences = {}
        @next_pref_id = 1
      end

      # Default preferences structure
      def default_preferences
        {
          theme: {
            color_scheme: 'light',
            font_size: 'medium',
            sidebar_collapsed: false
          },
          notifications: {
            email_enabled: true,
            push_enabled: false,
            frequency: 'daily',
            categories: %w[security billing product_updates]
          },
          privacy: {
            profile_visibility: 'private',
            analytics_tracking: false,
            marketing_emails: false
          },
          dashboard: {
            default_view: 'overview',
            widgets: %w[recent_activity quick_stats],
            refresh_interval: 300
          }
        }
      end

      # POST /preferences - Initialize user preferences
      def initialize_preferences(user_id, preferences_data)
        log_call(:initialize_preferences, { user_id: user_id, preferences_data: preferences_data })

        check_failure!(:initialize_preferences)

        # Check if preferences already exist
        existing_prefs = @preferences.values.find { |p| p[:user_id] == user_id }
        return mock_http_response(409, existing_prefs) if existing_prefs

        # Merge provided preferences with defaults
        user_preferences = default_preferences.deep_merge(preferences_data || {})

        preferences = {
          id: @next_pref_id,
          user_id: user_id,
          preferences: user_preferences,
          created_at: Time.current.iso8601,
          updated_at: Time.current.iso8601
        }

        @preferences[@next_pref_id] = preferences
        @next_pref_id += 1

        mock_http_response(201, preferences)
      end

      # GET /preferences/:user_id - Get user preferences
      def get_preferences(user_id)
        log_call(:get_preferences, { user_id: user_id })

        check_failure!(:get_preferences)

        user_prefs = @preferences.values.find { |p| p[:user_id] == user_id }

        if user_prefs
          mock_http_response(200, user_prefs)
        else
          # Return default preferences if none found
          fallback_preferences = {
            id: nil,
            user_id: user_id,
            preferences: default_preferences,
            created_at: Time.current.iso8601,
            updated_at: Time.current.iso8601,
            fallback: true
          }
          mock_http_response(200, fallback_preferences)
        end
      end

      # PUT /preferences/:user_id - Update user preferences
      def update_preferences(user_id, update_data)
        log_call(:update_preferences, { user_id: user_id, update_data: update_data })

        check_failure!(:update_preferences)

        user_prefs = @preferences.values.find { |p| p[:user_id] == user_id }

        return mock_http_response(404, { error: 'User preferences not found', user_id: user_id }) if user_prefs.nil?

        # Deep merge the updates
        user_prefs[:preferences] = user_prefs[:preferences].deep_merge(update_data)
        user_prefs[:updated_at] = Time.current.iso8601

        mock_http_response(200, user_prefs)
      end

      # GET /preferences/:user_id/category/:category - Get specific preference category
      def get_preference_category(user_id, category)
        log_call(:get_preference_category, { user_id: user_id, category: category })

        check_failure!(:get_preference_category)

        user_prefs = @preferences.values.find { |p| p[:user_id] == user_id }
        preferences = user_prefs ? user_prefs[:preferences] : default_preferences

        category_prefs = preferences[category.to_sym]

        if category_prefs
          mock_http_response(200, {
                               user_id: user_id,
                               category: category,
                               preferences: category_prefs,
                               updated_at: user_prefs ? user_prefs[:updated_at] : Time.current.iso8601
                             })
        else
          mock_http_response(404, { error: 'Preference category not found', category: category })
        end
      end

      # Reset service state
      def reset!
        @preferences.clear
        @next_pref_id = 1
      end

      # Configure failures for testing
      def configure_failures(method, options = {})
        self.class.stub_failure(method, StandardError, options[:message], fail_count: options[:fail_count])
      end

      private

      def check_failure!(method)
        # Let the base class handle failure simulation
        handle_response(method, {})
      end

      def mock_http_response(status, body)
        MockHttpResponse.new(status, body, {
                               'content-type' => 'application/json',
                               'x-response-time' => "#{rand(8..25)}ms",
                               'x-service' => 'preferences-service',
                               'x-version' => '1.0.3'
                             })
      end
    end
  end
end

# Helper method for deep merging hashes
class Hash
  def deep_merge(other_hash)
    dup.deep_merge!(other_hash)
  end

  def deep_merge!(other_hash)
    other_hash.each_pair do |key, value|
      self[key] = if self[key].is_a?(Hash) && value.is_a?(Hash)
                    self[key].deep_merge(value)
                  else
                    value
                  end
    end
    self
  end
end
