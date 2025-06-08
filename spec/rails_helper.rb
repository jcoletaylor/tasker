# frozen_string_literal: true

require 'logger'

# This file is copied to spec/ when you run 'rails generate rspec:install'
ENV['RAILS_ENV'] ||= 'test'

require 'spec_helper'

# Configure Rails Test Environment
require 'rails'
require 'active_support/railtie'
require 'action_controller/railtie'
require 'action_view/railtie'
require 'action_mailer/railtie'
require 'active_job/railtie'
require 'active_record/railtie'
require 'sidekiq'

# Load dummy application
require_relative 'dummy/config/environment'

# Prevent database truncation if the environment is production
abort('The Rails environment is running in production mode!') if Rails.env.production?

require 'rspec/rails'
# Add additional requires below this line

# Load FactoryBot if available
begin
  require 'factory_bot_rails'
rescue LoadError
  # FactoryBot not available, continue without it
end

# Requires supporting ruby files with custom matchers and macros, etc
Dir[File.join(File.dirname(__FILE__), 'support', '**', '*.rb')].each { |f| require f }

# Checks for pending migrations and applies them before tests are run.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  puts(e.to_s.strip)
  exit(1)
end

RSpec.configure do |config|
  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  config.fixture_paths = [Rails.root.join('spec/fixtures').to_s]

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, remove the following line or assign false
  # instead of true.
  config.use_transactional_fixtures = true

  # RSpec Rails can automatically mix in different behaviours to your tests
  # based on their file location, for example enabling you to call `get` and
  # `post` in specs under `spec/controllers`.
  config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!

  # Global authentication and configuration state cleanup
  # Ensures authentication coordinator and configuration are reset between tests to prevent state leakage
  config.around do |example|
    # Store original configuration state before test
    original_config = (Tasker::Configuration.instance_variable_get(:@configuration) if defined?(Tasker::Configuration))

    # Reset authentication coordinator before each test
    Tasker::Authentication::Coordinator.reset! if defined?(Tasker::Authentication::Coordinator)

    example.run
  ensure
    # Reset authentication coordinator after each test
    Tasker::Authentication::Coordinator.reset! if defined?(Tasker::Authentication::Coordinator)

    # Check if we have test-only configuration that needs cleanup
    if defined?(Tasker) && Tasker.respond_to?(:configuration)
      current_config = Tasker.configuration
      needs_reset = false

      # Check if using test-only authenticators
      if current_config&.auth&.strategy == :custom
        authenticator_class = current_config.auth.options[:authenticator_class] ||
                              current_config.auth.options['authenticator_class']
        needs_reset = true if authenticator_class&.include?('Test') || authenticator_class&.include?('Bad')
      end

      # Check if authorization is enabled (should be disabled by default)
      needs_reset = true if current_config&.auth&.enabled == true

      # Reset to defaults if needed
      if needs_reset
        Tasker.configuration do |config|
          config.auth.strategy = :none
          config.auth.options = {}
          config.auth.enabled = false
        end
        # Reset coordinator again after config change
        Tasker::Authentication::Coordinator.reset! if defined?(Tasker::Authentication::Coordinator)
      end
    end

    # Restore original configuration state after test if it was modified and it's clean
    if original_config && defined?(Tasker::Configuration)
      Tasker::Configuration.instance_variable_set(:@configuration, original_config)
      # Final coordinator reset after config restoration
      Tasker::Authentication::Coordinator.reset! if defined?(Tasker::Authentication::Coordinator)
    end
  end

  # FactoryBot Configuration
  if defined?(FactoryBot)
    config.include FactoryBot::Syntax::Methods

    # Configure FactoryBot before the test suite runs
    config.before(:suite) do
      # Configure FactoryBot paths for the engine
      engine_factory_path = File.expand_path('../spec/factories', __dir__)

      # Add engine factory paths if not already present
      unless FactoryBot.definition_file_paths.include?(engine_factory_path)
        FactoryBot.definition_file_paths << engine_factory_path
      end

      # Configure generators for FactoryBot (test environment only)
      if Rails.application.config.respond_to?(:generators)
        Rails.application.config.generators do |g|
          g.factory_bot suffix: 'factory'
          g.factory_bot dir: 'spec/factories/tasker'
        end
      end

      # Reload to pick up all factories
      FactoryBot.reload
    end

    # Clear factory state between tests to prevent pollution
    config.after do
      FactoryBot.rewind_sequences
    end
  end
end

require 'rspec-sidekiq'

RSpec::Sidekiq.configure do |config|
  # Clear all jobs between each test
  config.clear_all_enqueued_jobs = true
  # Warn when jobs are not enqueued to Redis but to a job array
  config.warn_when_jobs_not_processed_by_sidekiq = false
end
