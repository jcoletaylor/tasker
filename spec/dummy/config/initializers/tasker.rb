# frozen_string_literal: true

# Configure Tasker
Tasker.configuration do |config|
  config.engine do |engine|
    # Strategy for generating task identity hashes (options: :default, :hash, :custom)
    # :default - Uses a GUID/UUID for each task (no duplicate detection)
    # :hash - Uses SHA256 of task identity options (detects duplicates with same attributes)
    # :custom - Uses a custom strategy class specified in identity_strategy_class
    engine.identity_strategy = :hash

    # Directory within app/ where task handlers are stored (default: 'tasks')
    # engine.task_handler_directory = 'custom_tasks'

    # Directory within config/ where task YAML configs are stored (default: 'tasker/tasks')
    # engine.task_config_directory = 'custom_tasks'

    # Custom identity strategy class name (required if identity_strategy is :custom)
    # Must be a fully qualified class name that responds to #generate_identity_hash(task,task_options)
    # engine.identity_strategy_class = 'MyApp::CustomIdentityStrategy'
  end
end
