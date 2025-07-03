# frozen_string_literal: true

module BlogExamples
  module MockServices
    class MockUserService < BaseMockService
      def initialize
        super
        @service_name = 'user_service'
        @users = {}
        @next_user_id = 1
      end

      # POST /users - Create user account
      def create_user(user_data)
        log_call(:create_user, user_data)

        check_failure!(:create_user)

        email = user_data[:email] || user_data['email']

        # Check if user already exists (409 Conflict)
        existing_user = @users.values.find { |u| u[:email] == email }
        return mock_http_response(409, existing_user) if existing_user

        # Create new user
        user = {
          id: @next_user_id,
          email: email,
          name: user_data[:name] || user_data['name'],
          phone: user_data[:phone] || user_data['phone'],
          plan: user_data[:plan] || user_data['plan'] || 'free',
          status: 'pending',
          marketing_consent: user_data[:marketing_consent] || user_data['marketing_consent'] || false,
          referral_code: user_data[:referral_code] || user_data['referral_code'],
          source: user_data[:source] || user_data['source'] || 'web',
          created_at: Time.current.iso8601,
          updated_at: Time.current.iso8601
        }

        @users[@next_user_id] = user
        @next_user_id += 1

        mock_http_response(201, user)
      end

      # GET /users?email=email - Find user by email
      def get_user_by_email(email)
        log_call(:get_user_by_email, { email: email })

        check_failure!(:get_user_by_email)

        user = @users.values.find { |u| u[:email] == email }

        if user
          mock_http_response(200, user)
        else
          mock_http_response(404, { error: 'User not found', email: email })
        end
      end

      # PUT /users/:id/status - Update user status
      def update_user_status(user_id, status_data)
        log_call(:update_user_status, { user_id: user_id, status_data: status_data })

        check_failure!(:update_user_status)

        user = @users[user_id.to_i]

        return mock_http_response(404, { error: 'User not found', user_id: user_id }) if user.nil?

        # Update user status
        old_status = user[:status]
        user[:status] = status_data[:status] || status_data['status']
        user[:updated_at] = Time.current.iso8601

        # Add any additional status metadata
        if status_data[:metadata] || status_data['metadata']
          user[:status_metadata] = status_data[:metadata] || status_data['metadata']
        end

        response_data = {
          id: user[:id],
          email: user[:email],
          status: user[:status],
          previous_status: old_status,
          updated_at: user[:updated_at],
          status_metadata: user[:status_metadata]
        }.compact

        mock_http_response(200, response_data)
      end

      # GET /users/:id - Get user by ID
      def get_user(user_id)
        log_call(:get_user, { user_id: user_id })

        check_failure!(:get_user)

        user = @users[user_id.to_i]

        if user
          mock_http_response(200, user)
        else
          mock_http_response(404, { error: 'User not found', user_id: user_id })
        end
      end

      # Reset service state
      def reset!
        @users.clear
        @next_user_id = 1
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
                               'x-response-time' => "#{rand(10..50)}ms",
                               'x-service' => 'user-service',
                               'x-version' => '1.2.0'
                             })
      end
    end

    # Mock HTTP Response object to simulate Faraday::Response
    class MockHttpResponse
      attr_reader :status, :body, :headers

      def initialize(status, body, headers = {})
        @status = status
        @body = body
        @headers = headers
      end

      def success?
        (200..299).cover?(@status)
      end
    end
  end
end
