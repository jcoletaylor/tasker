# frozen_string_literal: true

# Shared context for isolating configuration state during tests
#
# This shared context ensures that:
# - Configuration changes don't leak between tests
# - Authentication coordinators are properly reset
# - Test authenticators are reset to clean state
#
# Usage:
#   RSpec.describe 'Some Integration Test' do
#     include_context 'configuration_test_isolation'
#
#     # Your tests here
#   end
RSpec.shared_context 'configuration_test_isolation' do
  around do |example|
    # Save original configuration state
    original_config = Tasker::Configuration.instance_variable_get(:@configuration)

    # Reset authentication coordinator state
    Tasker::Authentication::Coordinator.reset!

    # Reset test authenticator state if it exists
    TestAuthenticator.reset! if defined?(TestAuthenticator)

    # Run the test
    example.run
  ensure
    # Restore original configuration
    Tasker::Configuration.instance_variable_set(:@configuration, original_config)

    # Reset authentication coordinator state
    Tasker::Authentication::Coordinator.reset!

    # Reset test authenticator state if it exists
    TestAuthenticator.reset! if defined?(TestAuthenticator)
  end
end
