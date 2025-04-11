# frozen_string_literal: true

# This is an example initializer showing how to set up OpenTelemetry with Tasker
# Copy this file to config/initializers/opentelemetry.rb and customize as needed

require 'opentelemetry/sdk'
require 'opentelemetry-exporter-otlp'
# require 'opentelemetry/instrumentation/all'

# Configure OpenTelemetry
OpenTelemetry::SDK.configure do |c|
  # Set your service name
  c.service_name = 'dummy-service'

  # Use all auto-instrumentations that are available
  c.use_all
end
