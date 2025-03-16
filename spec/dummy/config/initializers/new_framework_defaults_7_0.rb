# typed: strict
# frozen_string_literal: true

# Be sure to restart your server when you modify this file.
#
# This file contains migration options to ease your Rails 7.0 upgrade.
# These defaults are already applied in application.rb via config.load_defaults '7.0'
# But they're documented here for reference and to ensure future-proofing.

# Rails 7.0 defaults
Rails.application.config.after_initialize do
  # ActiveSupport

  # Controls whether to use TimeZone.utc_to_local with a :utc offset for utc times
  # Rails.application.config.utc_to_local_returns_utc_offset_times = true

  # Controls whether to replace time zone in params with the local app zone
  # Rails.application.config.local_timezone_parsing = true

  # Rails 7.0 makes it such that ActiveSupport::Cache's memory and file stores use compression by default
  # Rails.application.config.active_support.use_cache_compression = true

  # ActionPack

  # Makes CSRF tokens authenticity work via session instead of via cookies
  # Sets cookies to SameSite=Lax by default (instead of nil), and allows setting SameSite: :strict
  # Rails.application.config.action_dispatch.cookies_same_site_protection = :lax

  # ActiveStorage

  # Deprecated default service setting
  # Rails.application.config.active_storage.service = :local

  # Configures the maximum duration of preview image processing
  # Rails.application.config.active_storage.video_preview_arguments =
  #   "-y -vframes 1 -f image2"

  # ActiveRecord

  # Warn about incorrect use of composite primary keys
  # Rails.application.config.active_record.verify_foreign_keys_for_fixtures = true

  # Verify that foreign key column specified by schema exists as a column
  # Rails.application.config.active_record.verify_foreign_key_column_for_fixtures = true

  # Disable partial inserts with empty columns
  # Rails.application.config.active_record.partial_inserts = false

  # Protect from open redirect attacks in ActiveRecord::Base#to_param
  # Rails.application.config.active_record.run_commit_callbacks_on_first_saved_instances_in_transaction = true

  # ActiveJob

  # Configure queues specified by a symbol to be treated as if a string
  # Rails.application.config.active_job.use_big_decimal_serialize = true
end
