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

  # Use all auto-instrumentations that are available
  c.use_all
end
