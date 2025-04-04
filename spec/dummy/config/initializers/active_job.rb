# typed: true
# frozen_string_literal: true

# Configure ActiveJob to use Sidekiq as the queue adapter
# This allows us to transition from direct Sidekiq usage to ActiveJob while
# maintaining compatibility with existing infrastructure
Rails.application.config.active_job.queue_adapter = :sidekiq

# Configure queue name mappings if needed
# Rails.application.config.active_job.queue_name_prefix = Rails.env
# Rails.application.config.active_job.queue_name_delimiter = '.'
