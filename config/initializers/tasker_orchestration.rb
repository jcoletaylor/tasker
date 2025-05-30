# frozen_string_literal: true

# Tasker Orchestration System Initializer
#
# This ensures the event-driven workflow orchestration system is always
# initialized during Rails application startup. TaskHandler.handle() now
# delegates to orchestration, making it the single workflow execution system.

Rails.application.config.after_initialize do
  # Initialize the orchestration system once Rails is fully loaded
  begin
    Tasker::Orchestration::Coordinator.initialize!
    Rails.logger.info("Tasker: Event-driven orchestration system initialized successfully")
  rescue StandardError => e
    Rails.logger.error("Tasker: Failed to initialize orchestration system: #{e.message}")
    raise
  end
end
