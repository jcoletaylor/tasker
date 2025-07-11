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

  def allow_debug?
    @allow_debug ||= ENV['TASKER_DEBUG'] == 'true'
  end

  def debug_log(message)
    puts "[DEBUG] #{message}" if allow_debug?
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

    workflows.each_with_index do |workflow, index|
      debug_log "Processing workflow #{index + 1}/#{workflows.count}: #{workflow.name} (ID: #{workflow.task_id})"

      # Bypass backoff timing for test environment to enable immediate retries
      TestOrchestration::TestCoordinator.bypass_backoff_for_testing([workflow])

      # Get the task handler for this workflow using base name extraction
      handler_name = extract_base_handler_name(workflow.name)
      debug_log "Handler name: #{handler_name}"

      handler = Tasker::HandlerFactory.instance.get(handler_name)
      debug_log "Handler found: #{handler.class.name}"

      # Configure the handler to use test strategies
      handler.workflow_coordinator_strategy = TestOrchestration::TestWorkflowCoordinator
      handler.reenqueuer_strategy = TestOrchestration::TestReenqueuer

      # Use the test coordinator's retry-aware execution
      test_coordinator = TestOrchestration::TestWorkflowCoordinator.new(
        reenqueuer_strategy: TestOrchestration::TestReenqueuer.new,
        max_retry_attempts: 5
      )

      debug_log 'Starting workflow execution...'

      # Debug SQL function directly before execution
      debug_log "Checking SQL function output for task #{workflow.task_id}:"
      step_statuses = Tasker::StepReadinessStatus.for_task(workflow.task_id)
      step_statuses.each do |status|
        debug_log "  SQL Function - Step #{status.name}: state=#{status.current_state}, retry_eligible=#{status.retry_eligible}, attempts=#{status.attempts}/#{status.retry_limit}, ready=#{status.ready_for_execution}"
      end

      # Also check the raw database state
      debug_log "Raw database state for task #{workflow.task_id}:"
      workflow.workflow_steps.each do |step|
        debug_log "  DB - Step #{step.name}: attempts=#{step.attempts}, retry_limit=#{step.retry_limit}, retryable=#{step.retryable}, in_process=#{step.in_process}, processed=#{step.processed}"

        # Check transitions
        latest_transition = step.workflow_step_transitions.where(most_recent: true).first
        debug_log "    Latest transition: #{latest_transition&.to_state} at #{latest_transition&.created_at}"
      end

      success = test_coordinator.execute_workflow_with_retries(workflow, handler)
      debug_log "Workflow execution result: #{success ? 'SUCCESS' : 'FAILED'}"

      # Check final workflow state
      workflow.reload
      debug_log "Final workflow status: #{workflow.status}"
      debug_log "Steps processed: #{workflow.workflow_steps.count(&:processed)}/#{workflow.workflow_steps.count}"

      # Debug step states
      workflow.workflow_steps.each do |step|
        debug_log "  Step #{step.name}: status=#{step.status}, processed=#{step.processed}, attempts=#{step.attempts}"
      end

      if success
        results[:successful_workflows] += 1
      else
        results[:failed_workflows] += 1
      end

      # Count processed steps
      results[:total_steps_processed] += workflow.workflow_steps.count(&:processed)
    end

    results[:total_execution_time] = Time.current - start_time
    results[:average_execution_time] = results[:total_execution_time] / workflows.count if workflows.any?

    debug_log "FINAL RESULTS: #{results[:successful_workflows]} successful, #{results[:failed_workflows]} failed"
    results
  end

  # Test SQL function performance with realistic data distributions
  #
  # This method focuses on validating that our SQL functions:
  # 1. Scale linearly with task count (not exponentially)
  # 2. Batch operations are significantly faster than individual calls
  # 3. Handle complex dependency graphs efficiently
  # 4. Maintain consistent performance across different workflow patterns
  #
  # @param task_count [Integer] Number of tasks to test with
  # @param workflows [Array<Tasker::Task>] Optional pre-created workflows to use
  # @return [Hash] Performance metrics proving function scalability
  def benchmark_function_performance(task_count: 50, workflows: nil)
    # Use provided workflows or create diverse dataset
    workflows ||= create_diverse_workflow_dataset(count: task_count)
    all_task_ids = workflows.map(&:task_id)

    # Create realistic data distribution by directly updating database
    # This simulates production-like state without complex state machine logic
    create_realistic_workflow_states(workflows)

    function_benchmarks = {}

    # Test 1: Individual function calls - should scale linearly
    start_time = Time.current
    individual_readiness_results = all_task_ids.map do |task_id|
      Tasker::StepReadinessStatus.for_task(task_id)
    end.flatten
    individual_time = Time.current - start_time

    function_benchmarks[:individual_step_readiness] = {
      execution_time: individual_time,
      record_count: individual_readiness_results.count,
      tasks_queried: all_task_ids.count,
      avg_time_per_task: individual_time / all_task_ids.count,
      query_type: 'Individual SQL function calls',
      scalability_metric: individual_time / task_count # Should be roughly constant
    }

    # Test 2: Batch function calls - should be significantly faster
    start_time = Time.current
    batch_readiness_results = Tasker::StepReadinessStatus.for_tasks(all_task_ids)
    batch_time = Time.current - start_time

    function_benchmarks[:batch_step_readiness] = {
      execution_time: batch_time,
      record_count: batch_readiness_results.count,
      tasks_queried: all_task_ids.count,
      avg_time_per_task: batch_time / all_task_ids.count,
      query_type: 'Batch SQL function',
      scalability_metric: batch_time / task_count,
      performance_improvement: individual_time / batch_time # Should be > 2x
    }

    # Test 3: TaskExecutionContext aggregation performance
    start_time = Time.current
    all_task_ids.filter_map do |task_id|
      Tasker::TaskExecutionContext.find(task_id)
    end
    individual_context_time = Time.current - start_time

    start_time = Time.current
    batch_context_results = Tasker::TaskExecutionContext.for_tasks(all_task_ids)
    batch_context_time = Time.current - start_time

    function_benchmarks[:task_execution_context_comparison] = {
      individual_time: individual_context_time,
      batch_time: batch_context_time,
      record_count: batch_context_results.count,
      tasks_queried: all_task_ids.count,
      performance_improvement: individual_context_time / batch_context_time,
      query_type: 'Aggregation function comparison'
    }

    # Test 4: Complex dependency analysis (what we're really testing)
    start_time = Time.current
    complex_workflows = workflows.select { |w| w.workflow_steps.count > 5 }
    complex_task_ids = complex_workflows.map(&:task_id)

    if complex_task_ids.any?
      complex_readiness = Tasker::StepReadinessStatus.for_tasks(complex_task_ids)
      complex_time = Time.current - start_time

      function_benchmarks[:complex_dependency_analysis] = {
        execution_time: complex_time,
        record_count: complex_readiness.count,
        tasks_queried: complex_task_ids.count,
        avg_steps_per_task: complex_readiness.count.to_f / complex_task_ids.count,
        query_type: 'Complex dependency graph analysis',
        complexity_handling: complex_time / complex_readiness.count # Time per dependency calculation
      }
    end

    # Test 5: Validate our core hypothesis - functions outperform views
    start_time = Time.current
    dag_relationships = Tasker::StepDagRelationship.all.to_a
    view_time = Time.current - start_time

    function_benchmarks[:view_comparison] = {
      view_execution_time: view_time,
      function_execution_time: batch_time,
      view_record_count: dag_relationships.count,
      function_record_count: batch_readiness_results.count,
      performance_advantage: view_time / batch_time, # Functions should be faster
      query_type: 'Function vs View performance comparison'
    }

    function_benchmarks
  end

  # Create realistic workflow state distribution for performance testing
  # This directly updates the database to simulate production-like conditions
  # without the overhead of state machine transitions
  def create_realistic_workflow_states(workflows)
    # Distribute workflows across realistic states:
    # 60% pending/in_progress, 30% complete, 10% error

    completed_count = (workflows.count * 0.3).to_i
    error_count = (workflows.count * 0.1).to_i

    # Complete some workflows (and their steps)
    workflows.first(completed_count).each do |workflow|
      # Add task completion transition
      workflow.task_transitions.create!(
        to_state: Tasker::Constants::TaskStatuses::COMPLETE,
        sort_key: 1,
        most_recent: true,
        metadata: { completed_by: 'performance_test_setup' }
      )

      # Mark all steps as complete
      workflow.workflow_steps.update_all(
        processed: true,
        processed_at: Time.current,
        updated_at: Time.current
      )

      # Add completion transitions for steps
      workflow.workflow_steps.each do |step|
        step.workflow_step_transitions.create!(
          to_state: Tasker::Constants::WorkflowStepStatuses::COMPLETE,
          sort_key: 1,
          most_recent: true,
          metadata: { completed_by: 'performance_test_setup' }
        )
      end
    end

    # Set some workflows to error state
    error_workflows = workflows[completed_count, error_count]
    error_workflows.each do |workflow|
      # Add task error transition
      workflow.task_transitions.create!(
        to_state: Tasker::Constants::TaskStatuses::ERROR,
        sort_key: 1,
        most_recent: true,
        metadata: { error_message: 'Simulated failure for performance testing' }
      )

      # Mark some steps as failed
      failed_steps = workflow.workflow_steps.sample([workflow.workflow_steps.count / 2, 1].max)
      failed_steps.each do |step|
        step.workflow_step_transitions.create!(
          to_state: Tasker::Constants::WorkflowStepStatuses::ERROR,
          sort_key: 1,
          most_recent: true,
          metadata: { error_message: 'Simulated failure for performance testing' }
        )
      end
    end

    # Remaining workflows stay in pending/in_progress (default state)
    # They already have the default pending state from creation
    Rails.logger.info "Performance test setup: #{completed_count} complete, #{error_count} error, #{workflows.count - completed_count - error_count} pending"
  end

  ##############################################################################
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
      # 1. Function performance testing
      if options[:include_performance]
        Rails.logger.info 'Running function performance tests...'
        report[:results][:function_performance] = benchmark_function_performance(
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
