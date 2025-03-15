# frozen_string_literal: true

require 'logger'

# This file is copied to spec/ when you run 'rails generate rspec:install'
ENV['RAILS_ENV'] ||= 'test'

require 'spec_helper'

# Required logger setup
require 'active_support'
require 'active_support/logger'
require 'active_support/tagged_logging'

# Configure Rails Test Environment
require 'rails'

# Prevent database truncation if the environment is production
abort('The Rails environment is running in production mode!') if Rails.env.production?

# Configure DidYouMean to suppress deprecation warnings
if defined?(DidYouMean)
  DidYouMean::SPELL_CHECKERS = {}
end

# Load dummy application
require_relative './dummy/config/environment'

require 'rspec/rails'
# Add additional requires below this line

# Requires supporting ruby files with custom matchers and macros, etc
Dir[Rails.root.join('spec/support/**/*.rb')].sort.each { |f| require f }

# Checks for pending migrations and applies them before tests are run.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  puts(e.to_s.strip)
  exit(1)
end

RSpec.configure do |config|
  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  config.fixture_path = Rails.root.join('spec/fixtures').to_s

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, remove the following line or assign false
  # instead of true.
  config.use_transactional_fixtures = true

  # You can uncomment this line to turn off ActiveRecord support entirely.
  # config.use_active_record = false

  # RSpec Rails can automatically mix in different behaviours to your tests
  # based on their file location, for example enabling you to call `get` and
  # `post` in specs under `spec/controllers`.
  #
  # The different available types are documented in the features, such as in
  # https://relishapp.com/rspec/rspec-rails/docs
  config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
  # arbitrary gems may also be filtered via:
  # config.filter_gems_from_backtrace("gem name")
end

require 'rspec-sidekiq'

RSpec::Sidekiq.configure do |config|
  # Clear all jobs between each test
  config.clear_all_enqueued_jobs = true
  # Warn when jobs are not enqueued to Redis but to a job array
  config.warn_when_jobs_not_processed_by_sidekiq = false
end
