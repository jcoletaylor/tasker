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
