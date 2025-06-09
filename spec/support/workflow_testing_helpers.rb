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
    # Activate test coordinator
    Tasker::Orchestration::TestCoordinator.activate!

    # Configure step failures if specified
    configure_failures.each do |step_name, config|
      Tasker::Orchestration::TestCoordinator.configure_step_failure(
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
    Tasker::Orchestration::TestCoordinator.deactivate!
    Tasker::Orchestration::TestCoordinator.clear_failure_patterns!
    Tasker::Testing::IdempotencyTestHandler.clear_execution_registry!
  end

  # Process workflows synchronously and gather performance metrics
  #
  # @param workflows [Array<Tasker::Task>] Workflows to process
  # @return [Hash] Performance and success metrics
  def process_workflows_with_metrics(workflows)
    return {} unless Tasker::Orchestration::TestCoordinator.active?

    start_time = Time.current

    # Process each workflow individually to get detailed metrics
    individual_results = workflows.map do |workflow|
      workflow_start = Time.current
      success = Tasker::Orchestration::TestCoordinator.process_task_synchronously(workflow)
      execution_time = Time.current - workflow_start

      workflow.reload

      {
        task_id: workflow.task_id,
        pattern: workflow.context['pattern'],
        success: success,
        execution_time: execution_time,
        step_count: workflow.workflow_steps.count,
        completed_steps: workflow.workflow_steps.count(&:processed),
        final_status: workflow.status
      }
    end

    total_time = Time.current - start_time

    # Calculate aggregate metrics
    {
      total_workflows: workflows.count,
      successful_workflows: individual_results.count { |r| r[:success] },
      failed_workflows: individual_results.count { |r| !r[:success] },
      total_execution_time: total_time,
      average_execution_time: total_time / workflows.count,
      total_steps_processed: individual_results.sum { |r| r[:completed_steps] },
      individual_results: individual_results,
      coordinator_stats: Tasker::Orchestration::TestCoordinator.execution_stats
    }
  end

  # Test database view performance with large datasets
  #
  # @param task_count [Integer] Number of tasks to test with
  # @return [Hash] Performance metrics for each view
  def benchmark_database_views(task_count: 50)
    # Create diverse dataset
    workflows = create_diverse_workflow_dataset(count: task_count)

    # Partially complete some workflows to create realistic state distribution
    workflows.sample(task_count / 3).each do |workflow|
      steps_to_complete = workflow.workflow_steps.sample(rand(1..3))
      steps_to_complete.each do |step|
        step.state_machine.transition_to!(:in_progress)
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
    return {} unless Tasker::Orchestration::TestCoordinator.active?

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
        Tasker::Orchestration::TestCoordinator.reenqueue_for_idempotency_test([task], reset_steps: true)
      end

      success = Tasker::Orchestration::TestCoordinator.process_task_synchronously(task)
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
        test_coordinator_active: Tasker::Orchestration::TestCoordinator.active?,
        coordinator_execution_stats: Tasker::Orchestration::TestCoordinator.execution_stats
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
