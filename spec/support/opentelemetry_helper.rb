# frozen_string_literal: true

RSpec.configure do |config|
  config.after(:suite) do
    # Safer cleanup approach - only flush if the tracer provider is responsive
    if defined?(OpenTelemetry) &&
       OpenTelemetry.respond_to?(:tracer_provider) &&
       OpenTelemetry.tracer_provider.respond_to?(:force_flush)

      begin
        # Use a timeout to prevent hanging
        Timeout.timeout(5) do
          OpenTelemetry.tracer_provider.force_flush
        end
      rescue Timeout::Error, StandardError => e
        # Log but don't fail - this is just cleanup
        puts "Warning: OpenTelemetry cleanup failed: #{e.message}"
      end
    end
  end
end
