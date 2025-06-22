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

  # Telemetry and observability configuration
  # Comprehensive observability with structured logging, metrics, and performance monitoring
  # config.telemetry do |tel|
  #   # === BASIC TELEMETRY SETTINGS ===
  #   tel.enabled = true
  #   tel.service_name = 'my_app_tasker'
  #   tel.service_version = '1.2.3'
  #
  #   # === STRUCTURED LOGGING (Phase 4.1 Complete) ===
  #   tel.structured_logging_enabled = true
  #   tel.correlation_id_header = 'X-Correlation-ID'  # HTTP header for correlation ID propagation
  #   tel.log_level = 'info'                          # debug, info, warn, error, fatal
  #   tel.log_format = 'json'                         # json, pretty_json, logfmt
  #
  #   # === SENSITIVE DATA FILTERING ===
  #   tel.filter_mask = '***REDACTED***'
  #   tel.filter_parameters = [:password, :api_key, 'credit_card.number', /token/i]
  #
  #   # === METRICS COLLECTION (Phase 4.2 Ready) ===
  #   tel.metrics_enabled = true
  #   tel.metrics_endpoint = '/tasker/metrics'         # Prometheus endpoint
  #   tel.metrics_format = 'prometheus'                # prometheus, json
  #   tel.metrics_auth_required = false               # Set to true for production
  #   tel.max_stored_samples = 1000                   # Memory limit for metrics
  #   tel.metrics_retention_hours = 24                # How long to keep metrics
  #
  #   # === PERFORMANCE MONITORING ===
  #   tel.performance_monitoring_enabled = true
  #   tel.slow_query_threshold_seconds = 1.0         # Detect slow operations
  #   tel.memory_threshold_mb = 100                   # Memory spike detection
  #   tel.event_sampling_rate = 1.0                   # 1.0 = 100%, 0.1 = 10% sampling
  #   tel.filtered_events = []                        # Events to exclude from collection
  #
  #   # === ADVANCED CONFIGURATION ===
  #   # tel.configure_telemetry({
  #   #   batch_events: false,                        # Enable event batching
  #   #   buffer_size: 100,                          # Events to buffer before flush
  #   #   flush_interval: 5,                         # Seconds between flushes
  #   #   async_processing: false,                   # Future: async event processing
  #   #   sampling_rate: 1.0                         # Event sampling rate
  #   # })
  # end

  # Dependency graph and bottleneck analysis configuration
  # These settings control how Tasker analyzes workflow dependencies,
  # identifies bottlenecks, and calculates impact scores for optimization.
  # config.dependency_graph do |graph|
  #   # Impact multipliers for bottleneck scoring calculations
  #   # These affect how different factors influence bottleneck impact scores
  #   graph.impact_multipliers = {
  #     downstream_weight: 5,      # Weight for downstream step count (higher = more impact)
  #     blocked_weight: 15,        # Weight for blocked step count (higher = more critical)
  #     path_length_weight: 10,    # Weight for critical path length
  #     completed_penalty: 15,     # Penalty for completed steps (reduce priority)
  #     blocked_penalty: 25,       # Penalty for blocked steps (increase priority)
  #     error_penalty: 30,         # Penalty for error steps (highest priority)
  #     retry_penalty: 10          # Penalty for retry steps (moderate priority)
  #   }
  #
  #   # Severity multipliers for state-based calculations
  #   # These adjust impact scores based on step states and conditions
  #   graph.severity_multipliers = {
  #     error_state: 2.0,          # Multiplier for steps in error state
  #     exhausted_retry_bonus: 0.5, # Additional multiplier for exhausted retries
  #     dependency_issue: 1.2       # Multiplier for dependency-related issues
  #   }
  #
  #   # Penalty constants for problematic step conditions
  #   # These add penalty points for specific retry and failure conditions
  #   graph.penalty_constants = {
  #     retry_instability: 3,      # Points per retry attempt (instability indicator)
  #     non_retryable: 10,         # Points for non-retryable failures
  #     exhausted_retry: 20        # Points for exhausted retry attempts
  #   }
  #
  #   # Severity thresholds for impact score classification
  #   # These determine when bottlenecks are classified as Critical/High/Medium/Low
  #   graph.severity_thresholds = {
  #     critical: 100,             # Score >= 100: Critical bottleneck
  #     high: 50,                  # Score >= 50: High priority bottleneck
  #     medium: 20                 # Score >= 20: Medium priority bottleneck
  #   }                            # Score < 20: Low priority
  #
  #   # Duration estimation constants for path analysis
  #   # These are used for calculating estimated execution times
  #   graph.duration_estimates = {
  #     base_step_seconds: 30,     # Estimated time per step (default)
  #     error_penalty_seconds: 60, # Additional time penalty for error steps
  #     retry_penalty_seconds: 30  # Additional time penalty per retry attempt
  #   }
  # end

  # Backoff and retry configuration
  # These settings control retry timing, exponential backoff calculations,
  # and task reenqueue delays for optimal failure recovery.
  # config.backoff do |backoff|
  #   # Default backoff progression for retry attempts (in seconds)
  #   # Each element represents the backoff time for that attempt number.
  #   # For attempts beyond this array, exponential backoff calculation is used.
  #   backoff.default_backoff_seconds = [1, 2, 4, 8, 16, 32]
  #
  #   # Maximum backoff time to cap exponential backoff calculations
  #   # Prevents excessively long delays between retry attempts
  #   backoff.max_backoff_seconds = 300  # 5 minutes maximum
  #
  #   # Multiplier for exponential backoff calculation
  #   # Formula: backoff_time = attempt_number ^ backoff_multiplier * base_seconds
  #   backoff.backoff_multiplier = 2.0
  #
  #   # Whether to apply jitter to backoff calculations
  #   # Helps prevent "thundering herd" when many steps retry simultaneously
  #   backoff.jitter_enabled = true
  #
  #   # Maximum jitter percentage for randomization
  #   # E.g., 0.1 means ±10% variation in backoff times
  #   backoff.jitter_max_percentage = 0.1
  #
  #   # Task reenqueue delays for different execution states
  #   # Controls how long to wait before retrying tasks in different states
  #   backoff.reenqueue_delays = {
  #     has_ready_steps: 0,              # Steps ready - immediate processing
  #     waiting_for_dependencies: 45,    # Waiting for dependencies - moderate delay
  #     processing: 10                   # Steps processing - short delay
  #   }
  #
  #   # Default reenqueue delay for unclear or unmatched states
  #   backoff.default_reenqueue_delay = 30
  #
  #   # Buffer time added to optimal backoff calculations
  #   # Ensures steps are definitely ready for retry when tasks are reenqueued
  #   backoff.buffer_seconds = 5
  # end
end
