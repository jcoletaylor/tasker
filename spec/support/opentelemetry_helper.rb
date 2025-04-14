# frozen_string_literal: true

RSpec.configure do |config|
  config.after(:suite) do
    # Force flush any pending spans to ensure they don't block test termination
    OpenTelemetry.tracer_provider.force_flush if defined?(OpenTelemetry) && OpenTelemetry.respond_to?(:tracer_provider)
  end
end
