# frozen_string_literal: true

require 'spec_helper'
require 'rails_helper'
require_relative 'example_jwt_authenticator'

RSpec.describe ExampleJWTAuthenticator do
  let(:test_secret) { 'super-secret-jwt-key-that-is-32-chars-plus' }
  let(:short_secret) { 'short' }
  let(:valid_options) do
    {
      secret: test_secret,
      algorithm: 'HS256',
      header_name: 'Authorization',
      user_class: 'JwtTestUser'
    }
  end

  let(:authenticator) { described_class.new(valid_options) }
  let(:mock_controller) { double('Controller') }
  let(:mock_request) { double('Request', headers: {}) }

  before do
    allow(mock_controller).to receive(:request).and_return(mock_request)
  end

  describe '#initialize' do
    it 'sets default values for optional parameters' do
      auth = described_class.new(secret: test_secret)

      expect(auth.send(:algorithm)).to eq('HS256')
      expect(auth.send(:header_name)).to eq('Authorization')
      expect(auth.send(:user_class)).to eq('User')
    end

    it 'allows custom configuration options' do
      custom_options = {
        secret: test_secret,
        algorithm: 'HS512',
        header_name: 'X-API-Token',
        user_class: 'ApiUser'
      }

      auth = described_class.new(custom_options)

      expect(auth.send(:algorithm)).to eq('HS512')
      expect(auth.send(:header_name)).to eq('X-API-Token')
      expect(auth.send(:user_class)).to eq('ApiUser')
    end
  end

  describe '#validate_configuration' do
    it 'returns no errors for valid configuration' do
      errors = authenticator.validate_configuration(valid_options)
      expect(errors).to be_empty
    end

    it 'requires JWT secret' do
      options = valid_options.except(:secret)
      errors = authenticator.validate_configuration(options)

      expect(errors).to include('JWT secret is required')
    end

    it 'validates secret length for security' do
      options = valid_options.merge(secret: short_secret)
      errors = authenticator.validate_configuration(options)

      expect(errors).to include('JWT secret should be at least 32 characters for security')
    end

    it 'validates JWT algorithm' do
      options = valid_options.merge(algorithm: 'INVALID')
      errors = authenticator.validate_configuration(options)

      expect(errors).to include(a_string_matching(/JWT algorithm must be one of:/))
    end

    it 'validates user class exists' do
      options = valid_options.merge(user_class: 'NonExistentUser')
      errors = authenticator.validate_configuration(options)

      expect(errors).to include("User class 'NonExistentUser' not found")
    end

    it 'accepts various valid JWT algorithms' do
      valid_algorithms = %w[HS256 HS384 HS512 RS256 RS384 RS512 ES256 ES384 ES512]

      valid_algorithms.each do |algorithm|
        options = valid_options.merge(algorithm: algorithm)
        errors = authenticator.validate_configuration(options)

        expect(errors).to be_empty, "Algorithm #{algorithm} should be valid"
      end
    end
  end

  describe 'JWT token generation and validation' do
    let(:user_id) { 1 }
    let(:valid_token) { described_class.generate_test_token(user_id: user_id, secret: test_secret) }
    let(:expired_token) do
      described_class.generate_test_token(
        user_id: user_id,
        secret: test_secret,
        expires_in: -1.hour # Expired 1 hour ago
      )
    end
    let(:invalid_signature_token) do
      described_class.generate_test_token(user_id: user_id, secret: 'wrong-secret')
    end

    describe '#current_user' do
      context 'with valid JWT token' do
        before do
          allow(mock_request).to receive(:headers).and_return({ 'Authorization' => "Bearer #{valid_token}" })
        end

        it 'returns the user' do
          user = authenticator.current_user(mock_controller)

          expect(user).to be_a(JwtTestUser)
          expect(user.id).to eq(1)
          expect(user.email).to eq('alice@example.com')
          expect(user.name).to eq('Alice Smith')
        end

        it 'memoizes the user' do
          user1 = authenticator.current_user(mock_controller)
          user2 = authenticator.current_user(mock_controller)

          expect(user1).to be(user2) # Same object instance
        end
      end

      context 'with token in different formats' do
        it 'extracts token from Bearer header' do
          allow(mock_request).to receive(:headers).and_return({ 'Authorization' => "Bearer #{valid_token}" })

          user = authenticator.current_user(mock_controller)
          expect(user).to be_present
        end

        it 'extracts raw token without Bearer prefix' do
          allow(mock_request).to receive(:headers).and_return({ 'Authorization' => valid_token })

          user = authenticator.current_user(mock_controller)
          expect(user).to be_present
        end

        it 'works with custom header name' do
          custom_auth = described_class.new(valid_options.merge(header_name: 'X-API-Token'))
          allow(mock_request).to receive(:headers).and_return({ 'X-API-Token' => valid_token })

          user = custom_auth.current_user(mock_controller)
          expect(user).to be_present
        end
      end

      context 'with invalid tokens' do
        it 'returns nil for expired token' do
          allow(mock_request).to receive(:headers).and_return({ 'Authorization' => "Bearer #{expired_token}" })

          user = authenticator.current_user(mock_controller)
          expect(user).to be_nil
        end

        it 'returns nil for token with invalid signature' do
          allow(mock_request).to receive(:headers).and_return({ 'Authorization' => "Bearer #{invalid_signature_token}" })

          user = authenticator.current_user(mock_controller)
          expect(user).to be_nil
        end

        it 'returns nil for malformed token' do
          allow(mock_request).to receive(:headers).and_return({ 'Authorization' => 'Bearer invalid.token.here' })

          user = authenticator.current_user(mock_controller)
          expect(user).to be_nil
        end

        it 'returns nil when no header is present' do
          allow(mock_request).to receive(:headers).and_return({})

          user = authenticator.current_user(mock_controller)
          expect(user).to be_nil
        end

        it 'returns nil when user is not found' do
          non_existent_user_token = described_class.generate_test_token(user_id: 999_999, secret: test_secret)
          allow(mock_request).to receive(:headers).and_return({ 'Authorization' => "Bearer #{non_existent_user_token}" })

          user = authenticator.current_user(mock_controller)
          expect(user).to be_nil
        end
      end
    end

    describe '#authenticated?' do
      context 'with valid token' do
        before do
          allow(mock_request).to receive(:headers).and_return({ 'Authorization' => "Bearer #{valid_token}" })
        end

        it 'returns true' do
          expect(authenticator.authenticated?(mock_controller)).to be true
        end
      end

      context 'with invalid token' do
        before do
          allow(mock_request).to receive(:headers).and_return({ 'Authorization' => 'Bearer invalid' })
        end

        it 'returns false' do
          expect(authenticator.authenticated?(mock_controller)).to be false
        end
      end

      context 'with no token' do
        before do
          allow(mock_request).to receive(:headers).and_return({})
        end

        it 'returns false' do
          expect(authenticator.authenticated?(mock_controller)).to be false
        end
      end
    end

    describe '#authenticate!' do
      context 'with valid token' do
        before do
          allow(mock_request).to receive(:headers).and_return({ 'Authorization' => "Bearer #{valid_token}" })
        end

        it 'succeeds without raising an error' do
          expect { authenticator.authenticate!(mock_controller) }.not_to raise_error
          expect(authenticator.authenticate!(mock_controller)).to be true
        end
      end

      context 'with invalid token' do
        before do
          allow(mock_request).to receive(:headers).and_return({ 'Authorization' => 'Bearer invalid' })
        end

        it 'raises AuthenticationError' do
          expect { authenticator.authenticate!(mock_controller) }
            .to raise_error(Tasker::Authentication::AuthenticationError, 'Invalid or missing JWT token')
        end
      end

      context 'with no token' do
        before do
          allow(mock_request).to receive(:headers).and_return({})
        end

        it 'raises AuthenticationError' do
          expect { authenticator.authenticate!(mock_controller) }
            .to raise_error(Tasker::Authentication::AuthenticationError, 'Invalid or missing JWT token')
        end
      end
    end
  end

  describe 'different user types' do
    let(:user_token) { described_class.generate_test_token(user_id: 1, secret: test_secret) }
    let(:admin_token) { described_class.generate_test_token(user_id: 2, secret: test_secret) }
    let(:super_admin_token) { described_class.generate_test_token(user_id: 999, secret: test_secret) }

    it 'loads different user types correctly' do
      # Test regular user
      user_auth = described_class.new(valid_options)
      user_controller = double('Controller')
      user_request = double('Request', headers: { 'Authorization' => "Bearer #{user_token}" })
      allow(user_controller).to receive(:request).and_return(user_request)

      user = user_auth.current_user(user_controller)
      expect(user.roles).to eq(['user'])
      expect(user.admin?).to be false

      # Test admin user
      admin_auth = described_class.new(valid_options)
      admin_controller = double('Controller')
      admin_request = double('Request', headers: { 'Authorization' => "Bearer #{admin_token}" })
      allow(admin_controller).to receive(:request).and_return(admin_request)

      admin = admin_auth.current_user(admin_controller)
      expect(admin.roles).to eq(['admin'])
      expect(admin.admin?).to be true
      expect(admin.email).to eq('bob@example.com')

      # Test super admin user
      super_admin_auth = described_class.new(valid_options)
      super_admin_controller = double('Controller')
      super_admin_request = double('Request', headers: { 'Authorization' => "Bearer #{super_admin_token}" })
      allow(super_admin_controller).to receive(:request).and_return(super_admin_request)

      super_admin = super_admin_auth.current_user(super_admin_controller)
      expect(super_admin.roles).to eq(%w[admin super_admin])
      expect(super_admin.admin?).to be true
      expect(super_admin.email).to eq('admin@example.com')
    end
  end

  describe 'error handling and logging' do
    before do
      # Mock Rails logger if it exists
      allow(Rails).to receive(:logger).and_return(double('Logger', warn: nil, error: nil, info: nil)) if defined?(Rails)
    end

    it 'handles JWT decode errors gracefully' do
      allow(mock_request).to receive(:headers).and_return({ 'Authorization' => 'Bearer totally.invalid.jwt' })

      expect { authenticator.current_user(mock_controller) }.not_to raise_error
      expect(authenticator.current_user(mock_controller)).to be_nil
    end

    it 'handles missing user class gracefully' do
      test_token = described_class.generate_test_token(user_id: 1, secret: test_secret)
      bad_auth = described_class.new(valid_options.merge(user_class: 'NonExistentUser'))
      allow(mock_request).to receive(:headers).and_return({ 'Authorization' => "Bearer #{test_token}" })

      expect { bad_auth.current_user(mock_controller) }.not_to raise_error
      expect(bad_auth.current_user(mock_controller)).to be_nil
    end
  end

  describe 'token generation utility' do
    describe '.generate_test_token' do
      it 'generates a valid JWT token' do
        token = described_class.generate_test_token(user_id: 42, secret: test_secret)

        expect(token).to be_a(String)
        expect(token.split('.').length).to eq(3) # JWT has 3 parts

        # Verify we can decode it
        payload, _header = JWT.decode(token, test_secret, true, { algorithm: 'HS256' })
        expect(payload['user_id']).to eq(42)
        expect(payload['iss']).to eq('tasker-test')
        expect(payload['aud']).to eq('tasker-api')
      end

      it 'supports custom algorithms' do
        token = described_class.generate_test_token(
          user_id: 42,
          secret: test_secret,
          algorithm: 'HS512'
        )

        payload, header = JWT.decode(token, test_secret, true, { algorithm: 'HS512' })
        expect(header['alg']).to eq('HS512')
        expect(payload['user_id']).to eq(42)
      end

      it 'supports custom expiration times' do
        token = described_class.generate_test_token(
          user_id: 42,
          secret: test_secret,
          expires_in: 2.hours
        )

        payload, _header = JWT.decode(token, test_secret, true, { algorithm: 'HS256' })

        # Token should expire approximately 2 hours from now
        expected_exp = 2.hours.from_now.to_i
        expect(payload['exp']).to be_within(60).of(expected_exp)
      end
    end
  end

  describe 'real-world integration scenarios' do
    it 'works with multiple concurrent requests' do
      # Simulate multiple different users with different tokens
      users_and_tokens = [
        { user_id: 1, token: described_class.generate_test_token(user_id: 1, secret: test_secret) },
        { user_id: 2, token: described_class.generate_test_token(user_id: 2, secret: test_secret) },
        { user_id: 999, token: described_class.generate_test_token(user_id: 999, secret: test_secret) }
      ]

      users_and_tokens.each do |user_data|
        # Create a new authenticator instance for each "request"
        auth = described_class.new(valid_options)
        controller = double('Controller')
        request = double('Request', headers: { 'Authorization' => "Bearer #{user_data[:token]}" })
        allow(controller).to receive(:request).and_return(request)

        user = auth.current_user(controller)
        expect(user.id).to eq(user_data[:user_id])
      end
    end

    it 'demonstrates configuration for different environments' do
      # Development configuration
      dev_config = {
        secret: 'development-secret-key-32-chars-min',
        algorithm: 'HS256',
        user_class: 'JwtTestUser'
      }

      # Production configuration (would use stronger algorithm)
      prod_config = {
        secret: 'production-secret-key-from-credentials-or-env-vars',
        algorithm: 'HS512', # Stronger algorithm for production
        user_class: 'User'
      }

      dev_auth = described_class.new(dev_config)
      described_class.new(prod_config)

      expect(dev_auth.validate_configuration(dev_config)).to be_empty
      # prod_auth validation will fail because 'User' class doesn't exist in test environment
      # but this demonstrates the configuration validation in action
    end
  end
end
