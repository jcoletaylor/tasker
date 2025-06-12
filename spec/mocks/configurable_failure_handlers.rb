# frozen_string_literal: true

require_relative '../../lib/tasker/step_handler/base'

module Tasker
  module Testing
    # Debug logging helper - can be controlled via environment variable
    def self.debug_log(message)
      puts "[DEBUG] #{message}" if ENV['TASKER_DEBUG'] == 'true'
    end
    # ConfigurableFailureHandler - A step handler that can be configured to fail
    # a specific number of times before succeeding, for testing retry logic
    class ConfigurableFailureHandler < Tasker::StepHandler::Base
      class_attribute :attempt_registry
      self.attempt_registry = {}

      attr_reader :step_name, :failure_count

      def initialize(step_name:, failure_count: 2, failure_message: 'Configurable test failure')
        super()
        @step_name = step_name
        @failure_count = failure_count
        @failure_message = failure_message
      end

      # Process method that implements configurable failure logic
      def process(task, _sequence, step)
        # Use step-specific key for attempt tracking
        attempt_key = "#{task.task_id}_#{step.workflow_step_id}_#{@step_name}"

        # Initialize or increment attempts for this specific step
        self.class.attempt_registry[attempt_key] ||= 0
        self.class.attempt_registry[attempt_key] += 1

        current_attempts = self.class.attempt_registry[attempt_key]

        Tasker::Testing.debug_log("ConfigurableFailureHandler.process called for #{@step_name}")
        Tasker::Testing.debug_log("attempt_key: #{attempt_key}, current_attempts: #{current_attempts}")

        # Check if TestCoordinator has configured failures for this step
        if TestOrchestration::TestCoordinator.active? &&
           TestOrchestration::TestCoordinator.failure_patterns[@step_name]

          pattern = TestOrchestration::TestCoordinator.failure_patterns[@step_name]
          pattern[:current_attempts] = current_attempts

          Tasker::Testing.debug_log("Using configured pattern for #{@step_name}: #{pattern.inspect}")

          if current_attempts <= pattern[:failure_count]
            # Store attempt info in step results for debugging
            step.results = {
              error: pattern[:failure_message],
              attempt: current_attempts,
              max_failures: pattern[:failure_count],
              will_succeed_next: current_attempts >= pattern[:failure_count]
            }

            Tasker::Testing.debug_log("#{@step_name} FAILING on attempt #{current_attempts} (configured)")
            Rails.logger.info("ConfigurableFailureHandler: #{@step_name} failing on attempt #{current_attempts} (configured)")
            raise StandardError, pattern[:failure_message]
          end
        elsif should_fail?(current_attempts)
          # Use default failure logic
          step.results = {
            error: @failure_message,
            attempt: current_attempts,
            max_failures: @failure_count,
            will_succeed_next: current_attempts >= @failure_count
          }

          Tasker::Testing.debug_log("#{@step_name} FAILING on attempt #{current_attempts} (default)")
          Rails.logger.info("ConfigurableFailureHandler: #{@step_name} failing on attempt #{current_attempts}")
          raise StandardError, @failure_message
        end

        # Success case - return meaningful results
        success_results = {
          success: true,
          step_name: @step_name,
          total_attempts: current_attempts,
          failed_attempts: current_attempts - 1,
          processed_at: Time.current,
          task_context_sample: task.context.slice(:batch_id, :workflow_type)
        }

        Tasker::Testing.debug_log("#{@step_name} SUCCEEDED after #{current_attempts} attempts")
        Rails.logger.info("ConfigurableFailureHandler: #{@step_name} succeeded after #{current_attempts} attempts")
        success_results
      end

      # Class method to clear attempt registry (for test cleanup)
      def self.clear_attempt_registry!
        self.attempt_registry = {}
      end

      private

      def should_fail?(current_attempts)
        current_attempts <= @failure_count
      end
    end

    # RandomFailureHandler - Fails randomly based on a probability
    class RandomFailureHandler < Tasker::StepHandler::Base
      def initialize(failure_probability: 0.3, failure_message: 'Random test failure')
        super()
        @failure_probability = failure_probability
        @failure_message = failure_message
        @attempt_count = 0
      end

      def process(task, _sequence, step)
        @attempt_count += 1

        if should_fail_randomly?
          step.results = {
            error: @failure_message,
            attempt: @attempt_count,
            failure_probability: @failure_probability,
            random_seed: Random.new_seed
          }

          Rails.logger.info("RandomFailureHandler: Random failure on attempt #{@attempt_count}")
          raise StandardError, @failure_message
        end

        {
          success: true,
          attempt: @attempt_count,
          random_success: true,
          task_id: task.task_id,
          processed_at: Time.current
        }
      end

      private

      def should_fail_randomly?
        rand < @failure_probability
      end
    end

    # NetworkTimeoutHandler - Simulates network timeouts and retries
    class NetworkTimeoutHandler < Tasker::StepHandler::Base
      class_attribute :attempt_registry
      self.attempt_registry = {}

      def initialize(timeout_count: 2, timeout_message: 'Network timeout')
        super()
        @timeout_count = timeout_count
        @timeout_message = timeout_message
      end

      def process(task, _sequence, step)
        # Use step-specific key for attempt tracking (same pattern as ConfigurableFailureHandler)
        attempt_key = "#{task.task_id}_#{step.workflow_step_id}_network_timeout"

        # Initialize or increment attempts for this specific step
        self.class.attempt_registry[attempt_key] ||= 0
        self.class.attempt_registry[attempt_key] += 1

        current_attempts = self.class.attempt_registry[attempt_key]

        if current_attempts <= @timeout_count
          step.results = {
            error: @timeout_message,
            attempt: current_attempts,
            timeout_simulation: true,
            retry_recommended: true,
            max_timeouts: @timeout_count
          }

          Rails.logger.info("NetworkTimeoutHandler: Simulating timeout #{current_attempts}/#{@timeout_count}")
          raise StandardError, @timeout_message
        end

        # Simulate successful network call
        {
          success: true,
          network_response: {
            status: 200,
            data: { message: "Success after #{current_attempts} attempts" },
            response_time_ms: rand(100..500)
          },
          total_attempts: current_attempts,
          failed_attempts: current_attempts - 1,
          task_context: task.context.slice(:batch_id)
        }
      end

      # Class method to clear attempt registry (for test cleanup)
      def self.clear_attempt_registry!
        self.attempt_registry = {}
      end
    end

    # IdempotencyTestHandler - Tests idempotent behavior
    class IdempotencyTestHandler < Tasker::StepHandler::Base
      class_attribute :execution_registry
      self.execution_registry = {}

      def initialize(step_name:)
        super()
        @step_name = step_name
      end

      def process(task, _sequence, step)
        execution_key = "#{task.task_id}_#{@step_name}"

        # Track executions for idempotency testing
        self.class.execution_registry[execution_key] ||= {
          first_execution_at: Time.current,
          execution_count: 0,
          results: nil
        }

        registry_entry = self.class.execution_registry[execution_key]
        registry_entry[:execution_count] += 1
        registry_entry[:last_execution_at] = Time.current

        # First execution - generate and store results
        if registry_entry[:execution_count] == 1
          results = generate_idempotent_results(task, step)
          registry_entry[:results] = results
          Rails.logger.info("IdempotencyTestHandler: First execution of #{@step_name}")
          results
        else
          # Subsequent executions - should return same results (idempotent)
          Rails.logger.info("IdempotencyTestHandler: Repeat execution #{registry_entry[:execution_count]} of #{@step_name}")

          # Verify idempotency by returning stored results
          stored_results = registry_entry[:results].dup
          stored_results[:idempotency_check] = {
            execution_count: registry_entry[:execution_count],
            first_executed_at: registry_entry[:first_execution_at],
            is_repeat_execution: true
          }

          stored_results
        end
      end

      # Class method to clear execution registry (for test cleanup)
      def self.clear_execution_registry!
        self.execution_registry = {}
      end

      # Class method to get execution statistics
      def self.execution_stats
        execution_registry.transform_values do |data|
          {
            execution_count: data[:execution_count],
            first_execution_at: data[:first_execution_at],
            last_execution_at: data[:last_execution_at]
          }
        end
      end

      private

      def generate_idempotent_results(task, step)
        {
          success: true,
          step_name: @step_name,
          task_id: task.task_id,
          step_id: step.workflow_step_id,
          generated_at: Time.current,
          # Deterministic data that should be same on re-execution
          checksum: Digest::MD5.hexdigest("#{task.task_id}_#{@step_name}"),
          sequence_number: step.workflow_step_id % 1000
        }
      end
    end

    # CompositeTestHandler - Combines multiple failure patterns
    class CompositeTestHandler < Tasker::StepHandler::Base
      def initialize(patterns: [])
        super()
        @patterns = patterns
        @execution_count = 0
      end

      def process(task, sequence, step)
        @execution_count += 1

        # Apply patterns in sequence
        @patterns.each_with_index do |pattern, index|
          return apply_pattern(pattern, task, sequence, step) if should_apply_pattern?(pattern, index)
        end

        # Default success if no patterns apply
        {
          success: true,
          patterns_processed: @patterns.size,
          execution_count: @execution_count,
          task_id: task.task_id
        }
      end

      private

      def should_apply_pattern?(pattern, _index)
        case pattern[:type]
        when :execution_range
          (pattern[:min_execution]..pattern[:max_execution]).cover?(@execution_count)
        when :probability
          rand < pattern[:probability]
        when :always
          true
        else
          false
        end
      end

      def apply_pattern(pattern, task, _sequence, step)
        case pattern[:action]
        when :fail
          step.results = pattern.merge(execution_count: @execution_count)
          raise StandardError, pattern[:message] || 'Composite pattern failure'
        when :delay
          sleep(pattern[:delay_seconds] || 0.1)
          { success: true, delayed: true, delay_seconds: pattern[:delay_seconds] }
        when :succeed
          pattern.merge(success: true, task_id: task.task_id, execution_count: @execution_count)
        end
      end
    end
  end
end

# Task handlers that use configurable failure step handlers
class ConfigurableFailureTask
  include Tasker::TaskHandler

  TASK_NAME = 'configurable_failure_task'

  # Step names
  RELIABLE_STEP = 'reliable_step'
  FLAKY_STEP = 'flaky_step'
  TIMEOUT_STEP = 'timeout_step'
  IDEMPOTENT_STEP = 'idempotent_step'

  register_handler(TASK_NAME)

  define_step_templates do |templates|
    templates.define(
      name: RELIABLE_STEP,
      description: 'Reliable step that always succeeds',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 0 } # Never fails
    )

    templates.define(
      name: FLAKY_STEP,
      description: 'Flaky step that fails twice then succeeds',
      depends_on_step: RELIABLE_STEP,
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 2 }
    )

    templates.define(
      name: TIMEOUT_STEP,
      description: 'Step that simulates network timeouts',
      depends_on_step: FLAKY_STEP,
      handler_class: Tasker::Testing::NetworkTimeoutHandler,
      handler_config: { timeout_count: 1 }
    )

    templates.define(
      name: IDEMPOTENT_STEP,
      description: 'Step that tests idempotent behavior',
      depends_on_step: TIMEOUT_STEP,
      handler_class: Tasker::Testing::IdempotencyTestHandler,
      handler_config: { step_name: IDEMPOTENT_STEP }
    )
  end

  def schema
    {
      type: 'object',
      properties: {
        test_scenario: { type: 'string' },
        batch_id: { type: 'string' }
      }
    }
  end

  # Override get_step_handler to properly instantiate configurable handlers
  def get_step_handler(step)
    handler_config = step_handler_config_map[step.name] || {}

    case step.name
    when RELIABLE_STEP, FLAKY_STEP
      Tasker::Testing::ConfigurableFailureHandler.new(
        step_name: step.name,
        **handler_config
      )
    when TIMEOUT_STEP
      Tasker::Testing::NetworkTimeoutHandler.new(**handler_config)
    when IDEMPOTENT_STEP
      Tasker::Testing::IdempotencyTestHandler.new(**handler_config)
    else
      super
    end
  end
end

# Complex Workflow Task Handlers using Step Templates
# These define different DAG patterns using Tasker's native step template system

# Linear workflow: Step1 → Step2 → Step3 → Step4 → Step5 → Step6
class LinearWorkflowTask
  include Tasker::TaskHandler

  TASK_NAME = 'linear_workflow_task'

  register_handler(TASK_NAME)

  define_step_templates do |templates|
    templates.define(
      name: 'initialize_data',
      description: 'Initialize workflow data',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 0 }
    )

    templates.define(
      name: 'validate_input',
      description: 'Validate input data',
      depends_on_step: 'initialize_data',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 0 }
    )

    templates.define(
      name: 'process_data',
      description: 'Process the data',
      depends_on_step: 'validate_input',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 1 }
    )

    templates.define(
      name: 'transform_results',
      description: 'Transform processed results',
      depends_on_step: 'process_data',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 0 }
    )

    templates.define(
      name: 'validate_output',
      description: 'Validate output data',
      depends_on_step: 'transform_results',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 0 }
    )

    templates.define(
      name: 'finalize_workflow',
      description: 'Finalize the workflow',
      depends_on_step: 'validate_output',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 0 }
    )
  end

  def schema
    {
      type: 'object',
      properties: {
        workflow_type: { type: 'string' },
        batch_id: { type: 'string' }
      }
    }
  end

  # Override get_step_handler to properly instantiate configurable handlers
  def get_step_handler(step)
    handler_config = step_handler_config_map[step.name] || {}

    case step.name
    when 'initialize_data', 'validate_input', 'process_data', 'transform_results', 'validate_output', 'finalize_workflow'
      Tasker::Testing::ConfigurableFailureHandler.new(
        step_name: step.name,
        **handler_config
      )
    else
      super
    end
  end
end

# Diamond workflow: Start → (Branch1, Branch2) → Merge → End
class DiamondWorkflowTask
  include Tasker::TaskHandler

  TASK_NAME = 'diamond_workflow_task'

  register_handler(TASK_NAME)

  define_step_templates do |templates|
    templates.define(
      name: 'start_workflow',
      description: 'Start the diamond workflow',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 0 }
    )

    # Parallel branches from start
    templates.define(
      name: 'branch_one_process',
      description: 'Process branch one data',
      depends_on_step: 'start_workflow',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 1 }
    )

    templates.define(
      name: 'branch_two_process',
      description: 'Process branch two data',
      depends_on_step: 'start_workflow',
      handler_class: Tasker::Testing::NetworkTimeoutHandler,
      handler_config: { timeout_count: 1 }
    )

    templates.define(
      name: 'branch_one_validate',
      description: 'Validate branch one results',
      depends_on_step: 'branch_one_process',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 0 }
    )

    templates.define(
      name: 'branch_two_validate',
      description: 'Validate branch two results',
      depends_on_step: 'branch_two_process',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 0 }
    )

    # Convergence point
    templates.define(
      name: 'merge_branches',
      description: 'Merge results from both branches',
      depends_on_steps: %w[branch_one_validate branch_two_validate],
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 0 }
    )

    templates.define(
      name: 'end_workflow',
      description: 'End the diamond workflow',
      depends_on_step: 'merge_branches',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 0 }
    )
  end

  def schema
    {
      type: 'object',
      properties: {
        workflow_type: { type: 'string' },
        batch_id: { type: 'string' }
      }
    }
  end

  # Override get_step_handler to properly instantiate configurable handlers
  def get_step_handler(step)
    handler_config = step_handler_config_map[step.name] || {}

    case step.name
    when 'start_workflow', 'branch_one_process', 'branch_one_validate', 'branch_two_validate', 'merge_branches', 'end_workflow'
      Tasker::Testing::ConfigurableFailureHandler.new(
        step_name: step.name,
        **handler_config
      )
    when 'branch_two_process'
      Tasker::Testing::NetworkTimeoutHandler.new(**handler_config)
    else
      super
    end
  end
end

# Parallel Merge workflow: Multiple independent parallel branches that all converge
class ParallelMergeWorkflowTask
  include Tasker::TaskHandler

  TASK_NAME = 'parallel_merge_workflow_task'

  register_handler(TASK_NAME)

  define_step_templates do |templates|
    # Independent parallel branches
    templates.define(
      name: 'fetch_user_data',
      description: 'Fetch user data independently',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 0 }
    )

    templates.define(
      name: 'fetch_order_data',
      description: 'Fetch order data independently',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 1 }
    )

    templates.define(
      name: 'fetch_inventory_data',
      description: 'Fetch inventory data independently',
      handler_class: Tasker::Testing::NetworkTimeoutHandler,
      handler_config: { timeout_count: 1 }
    )

    templates.define(
      name: 'fetch_pricing_data',
      description: 'Fetch pricing data independently',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 0 }
    )

    # Second level processing
    templates.define(
      name: 'process_user_data',
      description: 'Process user data',
      depends_on_step: 'fetch_user_data',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 0 }
    )

    templates.define(
      name: 'process_order_data',
      description: 'Process order data',
      depends_on_step: 'fetch_order_data',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 0 }
    )

    # Final convergence
    templates.define(
      name: 'merge_all_data',
      description: 'Merge all processed data',
      depends_on_steps: %w[process_user_data process_order_data fetch_inventory_data fetch_pricing_data],
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 1 }
    )
  end

  def schema
    {
      type: 'object',
      properties: {
        workflow_type: { type: 'string' },
        batch_id: { type: 'string' }
      }
    }
  end

  # Override get_step_handler to properly instantiate configurable handlers
  def get_step_handler(step)
    handler_config = step_handler_config_map[step.name] || {}

    case step.name
    when 'fetch_user_data', 'fetch_order_data', 'fetch_pricing_data', 'process_user_data', 'process_order_data', 'merge_all_data'
      Tasker::Testing::ConfigurableFailureHandler.new(
        step_name: step.name,
        **handler_config
      )
    when 'fetch_inventory_data'
      Tasker::Testing::NetworkTimeoutHandler.new(**handler_config)
    else
      super
    end
  end
end

# Tree workflow: Root → (Branch A, Branch B) → (A1, A2, B1, B2) → Leaf processing
class TreeWorkflowTask
  include Tasker::TaskHandler

  TASK_NAME = 'tree_workflow_task'

  register_handler(TASK_NAME)

  define_step_templates do |templates|
    # Root
    templates.define(
      name: 'root_initialization',
      description: 'Initialize the tree workflow',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 0 }
    )

    # First level branches
    templates.define(
      name: 'branch_a_setup',
      description: 'Set up branch A processing',
      depends_on_step: 'root_initialization',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 0 }
    )

    templates.define(
      name: 'branch_b_setup',
      description: 'Set up branch B processing',
      depends_on_step: 'root_initialization',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 1 }
    )

    # Second level - Branch A children
    templates.define(
      name: 'branch_a_task_one',
      description: 'Branch A task one',
      depends_on_step: 'branch_a_setup',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 0 }
    )

    templates.define(
      name: 'branch_a_task_two',
      description: 'Branch A task two',
      depends_on_step: 'branch_a_setup',
      handler_class: Tasker::Testing::NetworkTimeoutHandler,
      handler_config: { timeout_count: 1 }
    )

    # Second level - Branch B children
    templates.define(
      name: 'branch_b_task_one',
      description: 'Branch B task one',
      depends_on_step: 'branch_b_setup',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 0 }
    )

    templates.define(
      name: 'branch_b_task_two',
      description: 'Branch B task two',
      depends_on_step: 'branch_b_setup',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 1 }
    )

    # Final aggregation
    templates.define(
      name: 'aggregate_results',
      description: 'Aggregate all branch results',
      depends_on_steps: %w[branch_a_task_one branch_a_task_two branch_b_task_one branch_b_task_two],
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 0 }
    )
  end

  def schema
    {
      type: 'object',
      properties: {
        workflow_type: { type: 'string' },
        batch_id: { type: 'string' }
      }
    }
  end

  # Override get_step_handler to properly instantiate configurable handlers
  def get_step_handler(step)
    handler_config = step_handler_config_map[step.name] || {}

    case step.name
    when 'root_initialization', 'branch_a_setup', 'branch_b_setup', 'branch_a_task_one', 'branch_b_task_one', 'branch_b_task_two', 'aggregate_results'
      Tasker::Testing::ConfigurableFailureHandler.new(
        step_name: step.name,
        **handler_config
      )
    when 'branch_a_task_two'
      Tasker::Testing::NetworkTimeoutHandler.new(**handler_config)
    else
      super
    end
  end
end

# Mixed workflow: Complex pattern with various dependency types
class MixedWorkflowTask
  include Tasker::TaskHandler

  TASK_NAME = 'mixed_workflow_task'

  register_handler(TASK_NAME)

  define_step_templates do |templates|
    # Independent starting points
    templates.define(
      name: 'init_auth',
      description: 'Initialize authentication',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 0 }
    )

    templates.define(
      name: 'init_config',
      description: 'Initialize configuration',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 0 }
    )

    # Dependent on auth
    templates.define(
      name: 'validate_permissions',
      description: 'Validate user permissions',
      depends_on_step: 'init_auth',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 1 }
    )

    # Dependent on config
    templates.define(
      name: 'setup_environment',
      description: 'Set up processing environment',
      depends_on_step: 'init_config',
      handler_class: Tasker::Testing::NetworkTimeoutHandler,
      handler_config: { timeout_count: 1 }
    )

    # Dependent on both auth and config paths
    templates.define(
      name: 'begin_processing',
      description: 'Begin main processing',
      depends_on_steps: %w[validate_permissions setup_environment],
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 0 }
    )

    # Parallel processing branches
    templates.define(
      name: 'process_critical_data',
      description: 'Process critical data',
      depends_on_step: 'begin_processing',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 2 }
    )

    templates.define(
      name: 'process_optional_data',
      description: 'Process optional data',
      depends_on_step: 'begin_processing',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 0 }
    )

    # Independent cleanup that can run parallel to processing
    templates.define(
      name: 'cleanup_temp_files',
      description: 'Clean up temporary files',
      depends_on_step: 'setup_environment',
      handler_class: Tasker::Testing::ConfigurableFailureHandler,
      handler_config: { failure_count: 0 }
    )

    # Final step depends on critical processing and cleanup
    templates.define(
      name: 'finalize_and_report',
      description: 'Finalize processing and generate report',
      depends_on_steps: %w[process_critical_data cleanup_temp_files],
      handler_class: Tasker::Testing::IdempotencyTestHandler,
      handler_config: { step_name: 'finalize_and_report' }
    )
  end

  def schema
    {
      type: 'object',
      properties: {
        workflow_type: { type: 'string' },
        batch_id: { type: 'string' }
      }
    }
  end

  # Override get_step_handler to properly instantiate configurable handlers
  def get_step_handler(step)
    handler_config = step_handler_config_map[step.name] || {}

    case step.name
    when 'init_auth', 'init_config', 'validate_permissions', 'begin_processing', 'process_critical_data', 'process_optional_data', 'cleanup_temp_files'
      Tasker::Testing::ConfigurableFailureHandler.new(
        step_name: step.name,
        **handler_config
      )
    when 'setup_environment'
      Tasker::Testing::NetworkTimeoutHandler.new(**handler_config)
    when 'finalize_and_report'
      Tasker::Testing::IdempotencyTestHandler.new(**handler_config)
    else
      super
    end
  end
end
