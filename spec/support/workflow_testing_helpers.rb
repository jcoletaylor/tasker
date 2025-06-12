# frozen_string_literal: true

module WorkflowTestingHelpers
  # Helper methods for using the new workflow testing infrastructure
  # Provides convenient access to complex workflow factories, test coordination, and analysis

  # Create a diverse set of workflows for testing database views and orchestration
  #
  # @param count [Integer] Number of workflows to create (default: 20)
  # @param patterns [Array<Symbol>] Workflow patterns to include
  # @return [Array<Tasker::Task>] Created workflows
  def create_diverse_workflow_dataset(count: 20, patterns: nil)
    patterns ||= %i[linear_workflow diamond_workflow parallel_merge_workflow tree_workflow mixed_workflow]

    tasks = []
    pattern_cycle = patterns.cycle

    count.times do |i|
      pattern = pattern_cycle.next

      # Use the new step template-based factories directly
      factory_name = case pattern
                     when :linear_workflow
                       :linear_workflow_task
                     when :diamond_workflow
                       :diamond_workflow_task
                     when :parallel_merge_workflow
                       :parallel_merge_workflow_task
                     when :tree_workflow
                       :tree_workflow_task
                     when :mixed_workflow
                       :mixed_workflow_task
                     else
                       :linear_workflow_task # fallback
                     end

      tasks << create(factory_name,
                      context: {
                        batch_id: "test_dataset_#{Time.current.to_i}",
                        index: i,
                        pattern: pattern,
                        created_at: Time.current.to_f
                      })
    end

    tasks
  end

  # Create workflows with specific failure scenarios for testing retry logic
  #
  # @param failure_scenarios [Hash] Map of scenario names to failure configurations
  # @return [Array<Tasker::Task>] Created workflows with failure configurations
  def create_failure_test_workflows(failure_scenarios = {})
    default_scenarios = {
      reliable: { failure_step_names: [], completed_step_names: [] },
      partial_failure: { failure_step_names: %w[process_data], completed_step_names: %w[init_step] },
      early_failure: { failure_step_names: %w[init_step], completed_step_names: [] },
      retry_success: { failure_step_names: [], completed_step_names: %w[init_step fetch_data] }
    }

    scenarios = default_scenarios.merge(failure_scenarios)

    scenarios.map do |scenario_name, config|
      create(:diamond_workflow_task,
             context: {
               test_scenario: scenario_name,
               batch_id: "failure_test_#{scenario_name}",
               created_at: Time.current.to_f
             }.merge(config.fetch(:context, {})))
    end
  end

  # Setup test coordination for orchestration testing
  #
  # @param configure_failures [Hash] Step failure configurations
  # @return [void]
  def setup_test_coordination(configure_failures: {})
    # Load test orchestration components
    require_relative 'test_orchestration/test_coordinator'

    # Activate new test coordinator
    TestOrchestration::TestCoordinator.activate!

    # Configure step failures if specified
    configure_failures.each do |step_name, config|
      TestOrchestration::TestCoordinator.configure_step_failure(
        step_name.to_s,
        **config
      )
    end

    # Register test handlers if needed
    return if Tasker::HandlerFactory.instance.handler_classes.key?(:configurable_failure_task)

    Tasker::HandlerFactory.instance.register(
      ConfigurableFailureTask::TASK_NAME,
      ConfigurableFailureTask
    )

    # Register step template-based task handlers
    Tasker::HandlerFactory.instance.register(
      LinearWorkflowTask::TASK_NAME,
      LinearWorkflowTask
    )
    Tasker::HandlerFactory.instance.register(
      DiamondWorkflowTask::TASK_NAME,
      DiamondWorkflowTask
    )
    Tasker::HandlerFactory.instance.register(
      ParallelMergeWorkflowTask::TASK_NAME,
      ParallelMergeWorkflowTask
    )
    Tasker::HandlerFactory.instance.register(
      TreeWorkflowTask::TASK_NAME,
      TreeWorkflowTask
    )
    Tasker::HandlerFactory.instance.register(
      MixedWorkflowTask::TASK_NAME,
      MixedWorkflowTask
    )
  end

  # Cleanup test coordination and data
  #
  # @return [void]
  def cleanup_test_coordination
    TestOrchestration::TestCoordinator.deactivate!
    TestOrchestration::TestCoordinator.clear_failure_patterns!
    Tasker::Testing::IdempotencyTestHandler.clear_execution_registry!
    Tasker::Testing::ConfigurableFailureHandler.clear_attempt_registry!
  end

  # Process workflows synchronously and gather performance metrics
  #
  # @param workflows [Array<Tasker::Task>] Workflows to process
  # @return [Hash] Performance and success metrics
  def process_workflows_with_metrics(workflows)
    return {} unless TestOrchestration::TestCoordinator.active?

    results = {
      total_workflows: workflows.count,
      successful_workflows: 0,
      failed_workflows: 0,
      total_execution_time: 0,
      total_steps_processed: 0
    }

    start_time = Time.current

    workflows.each do |workflow|
      # Bypass backoff timing for test environment to enable immediate retries
      TestOrchestration::TestCoordinator.bypass_backoff_for_testing([workflow])

      # Get the task handler for this workflow using base name extraction
      handler_name = extract_base_handler_name(workflow.name)
      handler = Tasker::HandlerFactory.instance.get(handler_name)

      # Configure the handler to use test strategies
      handler.workflow_coordinator_strategy = TestOrchestration::TestWorkflowCoordinator
      handler.reenqueuer_strategy = TestOrchestration::TestReenqueuer

      # Use the test coordinator's retry-aware execution
      test_coordinator = TestOrchestration::TestWorkflowCoordinator.new(
        reenqueuer_strategy: TestOrchestration::TestReenqueuer.new,
        max_retry_attempts: 5
      )

      success = test_coordinator.execute_workflow_with_retries(workflow, handler)

      if success
        results[:successful_workflows] += 1
      else
        results[:failed_workflows] += 1
      end

      # Count processed steps
      workflow.reload
      results[:total_steps_processed] += workflow.workflow_steps.count(&:processed)
    end

    results[:total_execution_time] = Time.current - start_time
    results[:average_execution_time] = results[:total_execution_time] / workflows.count if workflows.count > 0
    results
  end

  # Test database view performance with large datasets
  #
  # @param task_count [Integer] Number of tasks to test with
  # @param workflows [Array<Tasker::Task>] Optional pre-created workflows to use instead of creating new ones
  # @return [Hash] Performance metrics for each view
  def benchmark_database_views(task_count: 50, workflows: nil)
    # Use provided workflows or create diverse dataset
    workflows ||= create_diverse_workflow_dataset(count: task_count)

    # Partially complete some workflows to create realistic state distribution
    workflows.sample(task_count / 3).each do |workflow|
      # Get steps in dependency order (topological sort) to avoid guard failures
      steps_in_order = get_steps_in_dependency_order(workflow)

      # Complete a random number of steps from the beginning of the dependency chain
      steps_to_complete_count = rand(1..3).clamp(1, steps_in_order.length)
      steps_to_complete = steps_in_order.first(steps_to_complete_count)

      steps_to_complete.each do |step|
        # Complete dependencies first to ensure state machine guards pass
        complete_step_dependencies_safely(step)

        # Use proper state machine transitions to avoid invalid transitions
        current_state = step.state_machine.current_state
        current_state = Tasker::Constants::WorkflowStepStatuses::PENDING if current_state.blank?

        # Only transition if not already complete
        completion_states = [
          Tasker::Constants::WorkflowStepStatuses::COMPLETE,
          Tasker::Constants::WorkflowStepStatuses::RESOLVED_MANUALLY
        ]

        next if completion_states.include?(current_state)

        # Transition to in_progress first if not already there
        unless current_state == Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS
          step.state_machine.transition_to!(:in_progress)
        end

        # Then transition to complete
        step.state_machine.transition_to!(:complete)
        step.update_columns(processed: true, processed_at: Time.current)
      end
    end

    # Benchmark each view
    view_benchmarks = {}

    # TaskWorkflowSummary performance
    start_time = Time.current
    summaries = Tasker::TaskWorkflowSummary.all.to_a
    view_benchmarks[:task_workflow_summary] = {
      execution_time: Time.current - start_time,
      record_count: summaries.count,
      query_complexity: 'HIGH - multiple aggregations and joins'
    }

    # StepReadinessStatus performance
    start_time = Time.current
    readiness_statuses = Tasker::StepReadinessStatus.all.to_a
    view_benchmarks[:step_readiness_status] = {
      execution_time: Time.current - start_time,
      record_count: readiness_statuses.count,
      query_complexity: 'MEDIUM - dependency calculations'
    }

    # StepDagRelationship performance
    start_time = Time.current
    dag_relationships = Tasker::StepDagRelationship.all.to_a
    view_benchmarks[:step_dag_relationships] = {
      execution_time: Time.current - start_time,
      record_count: dag_relationships.count,
      query_complexity: 'HIGH - recursive depth calculations'
    }

    view_benchmarks
  end

  # Create and execute idempotency test scenarios
  #
  # @param re_execution_count [Integer] Number of times to re-execute
  # @return [Hash] Idempotency test results
  def test_workflow_idempotency(re_execution_count: 3)
    return {} unless TestOrchestration::TestCoordinator.active?

    # Create a workflow with idempotent handlers
    task_request = Tasker::Types::TaskRequest.new(
      name: ConfigurableFailureTask::TASK_NAME,
      context: { test_scenario: 'idempotency_comprehensive', batch_id: 'idempotency_test' },
      initiator: 'test_system',
      reason: 'comprehensive_idempotency_testing'
    )

    handler = Tasker::HandlerFactory.instance.get(ConfigurableFailureTask::TASK_NAME)
    task = handler.initialize_task!(task_request)

    execution_results = []

    # Execute multiple times
    (re_execution_count + 1).times do |execution_index|
      start_time = Time.current

      if execution_index > 0
        # Reset for re-execution
        TestOrchestration::TestCoordinator.reenqueue_for_idempotency_test([task], reset_steps: true)
      end

      success = TestOrchestration::TestCoordinator.process_task_synchronously(task)
      execution_time = Time.current - start_time

      task.reload

      # Capture results for comparison
      step_results = task.workflow_steps.map do |step|
        {
          step_name: step.name,
          status: step.status,
          results_checksum: step.results.present? ? Digest::MD5.hexdigest(step.results.to_json) : nil,
          processed: step.processed,
          attempts: step.attempts
        }
      end

      execution_results << {
        execution_index: execution_index,
        success: success,
        execution_time: execution_time,
        task_status: task.status,
        step_results: step_results
      }
    end

    # Analyze idempotency
    first_execution = execution_results.first
    subsequent_executions = execution_results[1..]

    idempotency_violations = []

    subsequent_executions.each do |execution|
      # Compare with first execution
      execution[:step_results].each do |step_result|
        first_step = first_execution[:step_results].find { |s| s[:step_name] == step_result[:step_name] }

        # For idempotent steps, checksums should match
        unless (step_result[:step_name] == ConfigurableFailureTask::IDEMPOTENT_STEP) && (first_step[:results_checksum] != step_result[:results_checksum])
          next
        end

        idempotency_violations << {
          execution_index: execution[:execution_index],
          step_name: step_result[:step_name],
          violation_type: 'checksum_mismatch',
          expected: first_step[:results_checksum],
          actual: step_result[:results_checksum]
        }
      end
    end

    {
      total_executions: execution_results.count,
      all_executions_successful: execution_results.all? { |r| r[:success] },
      idempotency_violations: idempotency_violations,
      execution_results: execution_results,
      handler_execution_stats: Tasker::Testing::IdempotencyTestHandler.execution_stats
    }
  end

  # Extract base handler name by removing unique suffix
  def extract_base_handler_name(task_name)
    # Remove the unique suffix pattern: _timestamp_randomnumber
    # e.g., "linear_workflow_task_1749555645_529" -> "linear_workflow_task"
    task_name.gsub(/_\d+_\d+$/, '')
  end

  # Get steps in dependency order (topological sort) to avoid guard failures
  #
  # @param workflow [Tasker::Task] The workflow task
  # @return [Array<Tasker::WorkflowStep>] Steps in dependency order
  def get_steps_in_dependency_order(workflow)
    steps = workflow.workflow_steps.includes(:parents, :children).to_a

    # Simple topological sort - start with steps that have no dependencies
    ordered_steps = []
    remaining_steps = steps.dup

    while remaining_steps.any?
      # Find steps with no unprocessed dependencies
      ready_steps = remaining_steps.select do |step|
        step.parents.all? { |parent| ordered_steps.include?(parent) }
      end

      # If no steps are ready, we have a circular dependency or other issue
      # Just take the first remaining step to avoid infinite loop
      ready_steps = [remaining_steps.first] if ready_steps.empty?

      # Add ready steps to ordered list and remove from remaining
      ordered_steps.concat(ready_steps)
      remaining_steps -= ready_steps
    end

    ordered_steps
  end

  # Complete step dependencies safely to ensure state machine guards pass
  #
  # @param step [Tasker::WorkflowStep] The step whose dependencies to complete
  # @return [void]
  def complete_step_dependencies_safely(step)
    return unless step.respond_to?(:parents)

    parents = step.parents
    return if parents.blank?

    parents.each do |parent|
      # Check if parent is already complete
      completion_states = [
        Tasker::Constants::WorkflowStepStatuses::COMPLETE,
        Tasker::Constants::WorkflowStepStatuses::RESOLVED_MANUALLY
      ]
      current_state = parent.state_machine.current_state
      parent_status = current_state.presence || Tasker::Constants::WorkflowStepStatuses::PENDING

      # If parent isn't complete, complete it recursively
      next if completion_states.include?(parent_status)

      Rails.logger.debug do
        "Workflow Helper: Completing parent step #{parent.workflow_step_id} to satisfy dependency for step #{step.workflow_step_id}"
      end

      # Recursively complete parent's dependencies first
      complete_step_dependencies_safely(parent)

      # Then complete the parent
      begin
        unless parent_status == Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS
          parent.state_machine.transition_to!(:in_progress)
        end
        parent.state_machine.transition_to!(:complete)
        parent.update_columns(processed: true, processed_at: Time.current)
      rescue StandardError => e
        Rails.logger.warn "Could not complete parent step #{parent.workflow_step_id}: #{e.message}"
      end
    end
  end

  # Generate comprehensive test report for workflow infrastructure
  #
  # @param options [Hash] Test configuration options
  # @return [Hash] Comprehensive test report
  def generate_workflow_test_report(options = {})
    default_options = {
      dataset_size: 25,
      include_performance: true,
      include_idempotency: true,
      include_failure_scenarios: true,
      re_execution_count: 2
    }

    options = default_options.merge(options)

    report = {
      test_timestamp: Time.current,
      test_configuration: options,
      results: {}
    }

    # Setup test environment
    setup_test_coordination

    begin
      # 1. Database view performance testing
      if options[:include_performance]
        Rails.logger.info 'Running database view performance tests...'
        report[:results][:database_view_performance] = benchmark_database_views(
          task_count: options[:dataset_size]
        )
      end

      # 2. Orchestration testing with diverse workflows
      Rails.logger.info 'Running orchestration tests...'
      workflows = create_diverse_workflow_dataset(count: options[:dataset_size])
      report[:results][:orchestration_performance] = process_workflows_with_metrics(workflows)

      # 3. Failure scenario testing
      if options[:include_failure_scenarios]
        Rails.logger.info 'Running failure scenario tests...'
        failure_workflows = create_failure_test_workflows

        # Configure some failures for testing
        setup_test_coordination(configure_failures: {
                                  'process_a' => { failure_count: 1, failure_message: 'Transient failure' },
                                  'validate_data' => { failure_count: 2, failure_message: 'Validation timeout' }
                                })

        report[:results][:failure_scenario_performance] = process_workflows_with_metrics(failure_workflows)
      end

      # 4. Idempotency testing
      if options[:include_idempotency]
        Rails.logger.info 'Running idempotency tests...'
        report[:results][:idempotency_analysis] = test_workflow_idempotency(
          re_execution_count: options[:re_execution_count]
        )
      end

      # 5. Summary statistics
      report[:results][:summary] = {
        total_workflows_created: Tasker::Task.count,
        total_steps_created: Tasker::WorkflowStep.count,
        test_coordinator_active: TestOrchestration::TestCoordinator.active?,
        coordinator_execution_stats: TestOrchestration::TestCoordinator.execution_stats
      }
    ensure
      # Cleanup
      cleanup_test_coordination
    end

    report
  end
end

# Include helpers in RSpec
RSpec.configure do |config|
  config.include WorkflowTestingHelpers
end
