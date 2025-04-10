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

  config.observability do |observability|
    observability.enable_telemetry = true
    observability.telemetry_adapters = %w[
      Tasker::Observability::LoggerAdapter
      Tasker::Observability::OpenTelemetryAdapter
    ]
    observability.observer = 'Tasker::Observability::LifecycleObserver'
  end
end
