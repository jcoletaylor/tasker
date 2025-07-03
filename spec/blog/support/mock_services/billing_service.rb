# frozen_string_literal: true

module BlogExamples
  module MockServices
    class MockBillingService < BaseMockService
      def initialize
        super
        @service_name = 'billing_service'
        @profiles = {}
        @next_profile_id = 1
      end

      # POST /profiles - Create billing profile
      def create_profile(billing_data)
        log_call(:create_profile, billing_data)

        check_failure!(:create_profile)

        user_id = billing_data[:user_id] || billing_data['user_id']
        plan = billing_data[:plan] || billing_data['plan']

        # Check if profile already exists (409 Conflict)
        existing_profile = @profiles.values.find { |p| p[:user_id] == user_id }
        return mock_http_response(409, existing_profile) if existing_profile

        # For paid plans, require payment method
        if plan != 'free' && billing_data[:payment_method].nil? && billing_data['payment_method'].nil?
          return mock_http_response(402, {
                                      error: 'Payment method required for paid plans',
                                      plan: plan,
                                      required_fields: ['payment_method']
                                    })
        end

        # Create billing profile
        profile = {
          id: @next_profile_id,
          user_id: user_id,
          plan: plan,
          payment_method: billing_data[:payment_method] || billing_data['payment_method'],
          billing_address: billing_data[:billing_address] || billing_data['billing_address'],
          tax_id: billing_data[:tax_id] || billing_data['tax_id'],
          currency: billing_data[:currency] || billing_data['currency'] || 'USD',
          status: 'active',
          created_at: Time.current.iso8601,
          updated_at: Time.current.iso8601
        }

        @profiles[@next_profile_id] = profile
        @next_profile_id += 1

        mock_http_response(201, profile)
      end

      # Alias for step handler compatibility
      alias create_billing_profile create_profile

      # GET /profiles/:user_id - Get billing profile
      def get_profile(user_id)
        log_call(:get_profile, { user_id: user_id })

        check_failure!(:get_profile)

        profile = @profiles.values.find { |p| p[:user_id] == user_id }

        if profile
          mock_http_response(200, profile)
        else
          mock_http_response(404, { error: 'Billing profile not found', user_id: user_id })
        end
      end

      # PUT /profiles/:user_id - Update billing profile
      def update_profile(user_id, update_data)
        log_call(:update_profile, { user_id: user_id, update_data: update_data })

        check_failure!(:update_profile)

        profile = @profiles.values.find { |p| p[:user_id] == user_id }

        return mock_http_response(404, { error: 'Billing profile not found', user_id: user_id }) if profile.nil?

        # Update profile
        profile[:plan] = update_data[:plan] || update_data['plan'] || profile[:plan]
        profile[:payment_method] =
          update_data[:payment_method] || update_data['payment_method'] || profile[:payment_method]
        profile[:billing_address] =
          update_data[:billing_address] || update_data['billing_address'] || profile[:billing_address]
        profile[:tax_id] = update_data[:tax_id] || update_data['tax_id'] || profile[:tax_id]
        profile[:currency] = update_data[:currency] || update_data['currency'] || profile[:currency]
        profile[:updated_at] = Time.current.iso8601

        mock_http_response(200, profile)
      end

      # Reset service state
      def reset!
        @profiles.clear
        @next_profile_id = 1
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
                               'x-response-time' => "#{rand(15..75)}ms",
                               'x-service' => 'billing-service',
                               'x-version' => '2.1.0'
                             })
      end
    end
  end
end
