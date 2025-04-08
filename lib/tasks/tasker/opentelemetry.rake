# frozen_string_literal: true

namespace :tasker do
  namespace :telemetry do
    desc 'Setup OpenTelemetry for Tasker'
    task setup: :environment do
      # Copy example initializer if it doesn't exist
      initializer_path = Rails.root.join('config/initializers/opentelemetry.rb')
      example_initializer = File.expand_path('../../generators/tasker/templates/opentelemetry_initializer.rb', __dir__)

      if File.exist?(initializer_path)
        puts "OpenTelemetry initializer already exists at #{initializer_path}"
      else
        puts "Creating OpenTelemetry initializer at #{initializer_path}"
        FileUtils.cp(example_initializer, initializer_path)
      end

      # Add OpenTelemetry gems to Gemfile if they don't exist
      gemfile_path = Rails.root.join('Gemfile')
      gemfile_content = File.read(gemfile_path)

      otel_gems = [
        "gem 'opentelemetry-sdk'",
        "gem 'opentelemetry-instrumentation-all'"
      ]

      missing_gems = otel_gems.reject { |gem| gemfile_content.include?(gem) }

      if missing_gems.any?
        puts 'Adding OpenTelemetry gems to Gemfile'

        # Find a good location to add the gems
        # Try to find existing instrumentation or monitoring section
        lines = gemfile_content.lines
        insert_position = lines.index { |line| line =~ /monitoring|instrumentation|telemetry|observability/i }

        # If no specific section found, add after Rails gems
        insert_position ||= lines.index { |line| line =~ /gem ['"]rails['"]/i }

        # If still not found, add at the end of the file
        insert_position ||= lines.length - 1

        # Insert the gems
        lines.insert(insert_position + 1,
                     "\n# OpenTelemetry for distributed tracing\n#{missing_gems.join("\n")}\n")

        # Write the updated Gemfile
        File.write(gemfile_path, lines.join)

        puts 'Added OpenTelemetry gems to Gemfile'
        puts "Run 'bundle install' to install them"
      else
        puts 'OpenTelemetry gems already in Gemfile'
      end

      # Make sure the Tasker configuration is updated to include OpenTelemetry
      tasker_initializer_path = Rails.root.join('config/initializers/tasker.rb')

      if File.exist?(tasker_initializer_path)
        tasker_config = File.read(tasker_initializer_path)

        # Check if telemetry is already enabled and configured
        telemetry_enabled = tasker_config.match(/config\.enable_telemetry\s*=\s*true/)
        adapters_configured = tasker_config.match(/config\.telemetry_adapters\s*=/)

        if !telemetry_enabled || !adapters_configured
          puts 'Updating Tasker initializer to enable telemetry with OpenTelemetry'

          # If telemetry is not yet enabled, add the configuration
          if !telemetry_enabled
            # Find the right place to add config - before the end of the configuration block
            config_end = tasker_config.rindex(/end\s*\Z/)

            if config_end
              telemetry_config = "\n  # Enable telemetry with OpenTelemetry\n  " \
                                 "config.enable_telemetry = true\n  " \
                                 "config.telemetry_adapters = [:default, :opentelemetry]\n\n"

              updated_config = tasker_config.dup
              updated_config.insert(config_end, telemetry_config)

              File.write(tasker_initializer_path, updated_config)
              puts 'Enabled telemetry in Tasker configuration'
            else
              puts 'Could not update Tasker initializer automatically - please enable telemetry manually'
            end
          # If telemetry is enabled but adapters not configured, update them
          elsif !adapters_configured
            updated_config = tasker_config.gsub(
              /config\.enable_telemetry\s*=\s*true/,
              "config.enable_telemetry = true\n  config.telemetry_adapters = [:default, :opentelemetry]"
            )

            if updated_config != tasker_config
              File.write(tasker_initializer_path, updated_config)
              puts 'Added OpenTelemetry adapter to Tasker configuration'
            end
          end
        else
          puts 'Tasker initializer already configured for telemetry'
        end
      end

      puts "\nOpenTelemetry setup complete!"
      puts 'You may need to restart your Rails server for changes to take effect.'
      puts 'Edit config/initializers/opentelemetry.rb to customize your configuration.'
    end
  end
end
