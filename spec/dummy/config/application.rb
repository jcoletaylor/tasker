# typed: strict
# frozen_string_literal: true

require_relative 'boot'

require 'logger'
require 'rails'
require 'active_model/railtie'
require 'active_job/railtie'
require 'active_record/railtie'
require 'active_storage/engine'
require 'action_controller/railtie'
require 'action_mailer/railtie'
require 'action_view/railtie'
require 'action_cable/engine'
require 'rails/test_unit/railtie'

# Enable autoloading paths
lib_path = File.expand_path('../../../lib', __dir__)
$LOAD_PATH.unshift(lib_path) unless $LOAD_PATH.include?(lib_path)

# Require the gems listed in Gemfile
require 'bundler/setup'
Bundler.require(*Rails.groups)
require 'tasker'

require 'logger'
require 'active_support'
require 'active_support/logger'
require 'active_support/tagged_logging'

# Configure global logger
logger = ActiveSupport::TaggedLogging.new(Logger.new($stdout))
logger.level = Logger::INFO
Rails.logger = logger

module Dummy
  class Application < Rails::Application
    # Prevent the framework from freezing configurations too early
    config.before_initialize do
      # Ensure test environment settings
      if Rails.env.test?
        config.cache_classes = false
        config.eager_load = false
        config.enable_reloading = true
        config.allow_concurrency = true
        # Disable constant autoloading during initialization
        config.autoloader = :classic
      end
    end

    # Load defaults but allow for modifications
    config.load_defaults '7.0'
    
    # Allow concurrency in all environments
    config.allow_concurrency = true

    # Configuration for the application, engines, and railties goes here.
    config.api_only = true
    config.eager_load_paths << Rails.root.join('lib')

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.

    # Rails 7.0 defaults that are explicitly added to application.rb
    # Defaults to true in Rails 7 - controls whether ActiveSupport::TimeZone.utc_to_local
    # returns a time with an unspecified offset or a time with a zero offset
    config.utc_to_local_returns_utc_offset_times = true

    # Defaults to true in Rails 7 - controls whether to replace existing time zones
    # in +:in+ option from +ActiveSupport::TimeZone.parse+ with the current default time zone
    config.local_timezone_parsing = true

    # Defaults to true in Rails 7 - makes CSRF tokens store SameSite
    # as they are cookie-adjacent
    config.action_controller.urlsafe_csrf_tokens = true

    # Defaults to true in Rails 7 - makes cookies use SameSite=Lax
    # by default, and changes the default value of the
    # same_site option from nil to :lax
    config.action_dispatch.cookies_same_site_protection = :lax
  end
end
