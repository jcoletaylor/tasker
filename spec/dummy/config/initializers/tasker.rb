# frozen_string_literal: true

# Configure Tasker
Tasker.configuration do |config|
  # Engine configuration
  config.engine do |engine|
    #   engine.task_handler_directory = 'custom_tasks'
    #   engine.task_config_directory = 'custom_tasks'
    #   engine.default_module_namespace = 'OurTasks'

    engine.identity_strategy = :hash
    #   engine.identity_strategy_class = 'MyApp::CustomIdentityStrategy'
  end

  # Authentication and authorization configuration
  # config.auth do |auth|
  #   auth.strategy = :devise
  #   auth.options = { scope: :user }
  #   auth.enabled = true
  #   auth.coordinator_class = 'MyApp::AuthorizationCoordinator'
  #   auth.user_class = 'User'
  # end

  # Database configuration
  # config.database do |db|
  #   db.enable_secondary_database = true
  #   db.name = :tasker
  # end

  # Telemetry configuration
  # config.telemetry do |tel|
  # tel.enabled = false
  #   tel.service_name = 'my_app_tasker'
  #   tel.service_version = '1.2.3'
  #   tel.filter_mask = '***REDACTED***'
  #   tel.filter_parameters = [:password, :api_key, 'credit_card.number', /token/i]
  # end
end
