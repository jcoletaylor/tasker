# frozen_string_literal: true

# This is an example initializer showing how to set up OpenTelemetry with Tasker
# Copy this file to config/initializers/opentelemetry.rb and customize as needed

require 'opentelemetry/sdk'
require 'opentelemetry-exporter-otlp'
require 'opentelemetry/instrumentation/all'

# Configure OpenTelemetry
OpenTelemetry::SDK.configure do |c|
  # Use the configured service name
  c.service_name = Tasker::Configuration.configuration.otel_telemetry_service_name

  # Configure OTLP exporter to send to local Jaeger
  otlp_exporter = OpenTelemetry::Exporter::OTLP::Exporter.new(
    endpoint: 'http://localhost:4318/v1/traces'
  )

  # Add the OTLP exporter
  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(otlp_exporter)
  )

  # Configure resource with additional attributes
  c.resource = OpenTelemetry::SDK::Resources::Resource.create({
                                                                'service.name' => Tasker::Configuration.configuration.otel_telemetry_service_name,
                                                                'service.version' => Tasker::Configuration.configuration.otel_telemetry_service_version,
                                                                'service.framework' => 'tasker'
                                                              })

  # ✅ ENHANCED: PG instrumentation re-enabled after memory and connection management improvements
  # Tasker v1.6+ includes fixes for:
  # - Database connection pooling with ActiveRecord::Base.connection_pool.with_connection
  # - Memory leak prevention with explicit futures.clear() calls
  # - Batched concurrent processing (MAX_CONCURRENT_STEPS = 3) to prevent connection exhaustion
  # - Proper error persistence ensuring no dangling database connections

  # Use all auto-instrumentations except Faraday (which has a known bug)
  # The Faraday instrumentation incorrectly passes Faraday::Response objects instead of status codes
  # causing "undefined method `to_i' for #<Faraday::Response>" errors
  #
  # If you want to enable Faraday instrumentation, use:
  # c.use_all
  #
  # For now, we exclude it to prevent API step handler failures:
  c.use_all({ 'OpenTelemetry::Instrumentation::Faraday' => { enabled: false } })
end
