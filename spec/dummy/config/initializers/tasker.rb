# frozen_string_literal: true

# Configure Tasker task directories
Tasker.configuration do |config|
  # Directory within app/ where task handlers are stored (default: 'tasks')
  # config.task_handler_directory = 'custom_tasks'

  # Directory within config/ where task YAML configs are stored (default: 'tasks')
  # config.task_config_directory = 'workflows'

  # Strategy for generating task identity hashes (options: :default, :hash, :custom)
  # :default - Uses a GUID/UUID for each task (no duplicate detection)
  # :hash - Uses SHA256 of task identity options (detects duplicates with same attributes)
  # :custom - Uses a custom strategy class specified in identity_strategy_class
  # config.identity_strategy = :hash

  # Custom identity strategy class name (required if identity_strategy is :custom)
  # Must be a fully qualified class name that responds to #generate_identity_hash(task,task_options)
  # config.identity_strategy_class = 'MyApp::CustomIdentityStrategy'

  config.identity_strategy = :hash

  # Enable telemetry for tasks and steps (default: false)
  config.enable_telemetry = true

  # Telemetry adapters to use (options: :default, :opentelemetry, :custom)
  # :default - Uses Rails.logger
  # :opentelemetry - Uses OpenTelemetry for distributed tracing
  # :custom - Uses custom adapter classes specified in telemetry_adapter_classes
  # You can use multiple adapters simultaneously, e.g.:
  # config.telemetry_adapters = [:default, :opentelemetry]

  config.telemetry_adapters = %i[default opentelemetry]

  # Custom telemetry adapter class names (required when using :custom in telemetry_adapters)
  # Must be an array of fully qualified class names that implement the telemetry adapter interface
  # The array indices should correspond to the :custom entries in telemetry_adapters
  # config.telemetry_adapter_classes = ['MyApp::CustomTelemetryAdapter']
end
