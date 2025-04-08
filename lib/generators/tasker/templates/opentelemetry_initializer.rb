# frozen_string_literal: true

# This is an example initializer showing how to set up OpenTelemetry with Tasker
# Copy this file to config/initializers/opentelemetry.rb and customize as needed

require 'opentelemetry/sdk'
require 'opentelemetry/instrumentation/all'

# Configure OpenTelemetry
OpenTelemetry::SDK.configure do |c|
  # Set your service name
  c.service_name = 'tasker-user-service'

  # Use all auto-instrumentations that are available
  c.use_all
end

# Configure Tasker to use OpenTelemetry
# Tasker.configuration do |config|
  # Enable telemetry
  # config.enable_telemetry = true

  # Use both the default Rails logger and OpenTelemetry adapters
  # This ensures you have basic logging plus distributed tracing
  # config.telemetry_adapters = %i[default opentelemetry]

  # If you want to use only OpenTelemetry, uncomment this line instead:
  # config.telemetry_adapters = [:opentelemetry]
# end
