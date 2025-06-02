# frozen_string_literal: true

# Factory-based workflow helpers to replace manual task creation and step manipulation
# This replaces the imperative patterns from Helpers::TaskHelpers with declarative factory patterns
module FactoryWorkflowHelpers
  # Simple struct to replace sequence objects during migration
  # Provides compatibility while we transition away from imperative sequence objects
  SequenceStruct = Struct.new(:steps, :task) do
    def find_step_by_name(name)
      task.workflow_steps.joins(:named_step).find_by(named_step: { name: name })
    end
  end

  # Create a dummy task workflow with proper state machine setup
  def create_dummy_task_workflow(options = {})
    create(:dummy_task_workflow, **options, with_dependencies: true)
  end

  # Create a dummy task workflow ready for event-driven orchestration
  # This creates tasks and steps in their initial pending state, ready for processing
  def create_dummy_task_for_orchestration(options = {})
    create(:dummy_task_workflow, :for_orchestration, **options, with_dependencies: true)
  end

  # Create a dummy task workflow variant (mimics DUMMY_TASK_TWO)
  def create_dummy_task_two_workflow(options = {})
    create(:dummy_task_workflow, :dummy_task_two, **options, with_dependencies: true)
  end

  # Create API integration workflow (replacement for manual task creation in integration tests)
  def create_api_integration_workflow(options = {})
    cart_id = options.delete(:cart_id) || 1
    context = { cart_id: cart_id }
    task = create(:api_integration_workflow, **options, context: context, with_dependencies: true)

    register_task_handler(ApiTask::IntegrationExample::TASK_REGISTRY_NAME, ApiTask::IntegrationExample)

    task
  end

  # Find step by name in task (replacement for sequence.find_step_by_name)
  def find_step_by_name(task, step_name)
    task.workflow_steps.joins(:named_step).find_by(named_step: { name: step_name })
  end

  # Complete a step using state machine (replacement for helper.mark_step_complete)
  def complete_step_via_state_machine(step)
    # Handle dependencies first - complete any parent steps that aren't already complete
    complete_step_dependencies(step)

    # Get current state - be defensive about state transitions
    current_state = step.state_machine.current_state
    current_state = Tasker::Constants::WorkflowStepStatuses::PENDING if current_state.blank?

    # Only transition if not already complete
    completion_states = [
      Tasker::Constants::WorkflowStepStatuses::COMPLETE,
      Tasker::Constants::WorkflowStepStatuses::RESOLVED_MANUALLY
    ]

    unless completion_states.include?(current_state)
      # Transition to in_progress if not already there
      unless current_state == Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS
        step.state_machine.transition_to!(:in_progress)
      end

      # Transition to complete
      step.state_machine.transition_to!(:complete)
    end

    # Always ensure step data is properly set for completed state
    step.update_columns(
      processed: true,
      processed_at: Time.current,
      results: { dummy: true, other: true }
    )
    step
  end

  # Complete multiple steps for API integration testing (replacement for complete_steps helper)
  def complete_prerequisite_steps(task, step_names)
    step_names.each do |step_name|
      step = find_step_by_name(task, step_name)
      complete_step_with_results(step, step_name)
    end
  end

  # Complete step with realistic results for API integration (replacement for task_handler.handle_one_step)
  def complete_step_with_results(step, step_name = nil)
    step_name ||= step.named_step.name

    # Get current state and be defensive about transitions
    current_state = step.state_machine.current_state
    current_state = Tasker::Constants::WorkflowStepStatuses::PENDING if current_state.blank?

    # Only transition through in_progress if not already complete
    completion_states = [
      Tasker::Constants::WorkflowStepStatuses::COMPLETE,
      Tasker::Constants::WorkflowStepStatuses::RESOLVED_MANUALLY
    ]

    unless completion_states.include?(current_state)
      # Set step to in progress if not already there or beyond
      unless [
        Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS,
        Tasker::Constants::WorkflowStepStatuses::COMPLETE,
        Tasker::Constants::WorkflowStepStatuses::RESOLVED_MANUALLY
      ].include?(current_state)
        step.state_machine.transition_to!(:in_progress)
      end

      # Set step-specific results based on step name
      results = case step_name
                when 'fetch_cart'
                  { cart: { id: 1, items: [{ product_id: 1, quantity: 2 }] } }
                when 'fetch_products'
                  { products: [{ id: 1, name: 'Test Product', in_stock: true }] }
                when 'validate_products'
                  { valid_products: [{ id: 1, validated: true }] }
                when 'create_order'
                  { order_id: SecureRandom.uuid }
                when 'publish_event'
                  { published: true, publish_results: { status: 'placed_pending_fulfillment' } }
                else
                  { dummy: true, other: true }
                end

      # Complete step with results
      step.state_machine.transition_to!(:complete)
      step.update_columns(
        processed: true,
        processed_at: Time.current,
        results: results
      )
    end

    step
  end

  # Reset step to pending using state machine (replacement for helper.reset_step_to_default)
  def reset_step_to_pending(step)
    # If step is not in pending state, we need to carefully handle the reset
    current_state = step.state_machine.current_state

    unless current_state == Tasker::Constants::WorkflowStepStatuses::PENDING
      # For testing purposes, manually reset the state
      # In production, this would be handled through proper workflow retry mechanisms
      step.update_columns(
        processed: false,
        processed_at: nil,
        in_process: false,
        results: { dummy: true }
      )

      # Handle case where step might not have any transitions yet
      max_sort_key = step.workflow_step_transitions.maximum(:sort_key) || 0

      # Create a new transition to pending state
      create(:workflow_step_transition,
             workflow_step: step,
             to_state: Tasker::Constants::WorkflowStepStatuses::PENDING,
             sort_key: max_sort_key + 1,
             most_recent: true)

      # Update previous transition to not be most recent
      step.workflow_step_transitions.where(most_recent: true)
          .where.not(id: step.workflow_step_transitions.last.id)
          .update_all(most_recent: false)
    end

    step
  end

  # Set step to in_progress (replacement for step.update!({ in_process: true }))
  def set_step_in_progress(step)
    current_state = step.state_machine.current_state
    current_state = Tasker::Constants::WorkflowStepStatuses::PENDING if current_state.blank?

    # Only transition if not already in progress or beyond
    unless [
      Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS,
      Tasker::Constants::WorkflowStepStatuses::COMPLETE,
      Tasker::Constants::WorkflowStepStatuses::RESOLVED_MANUALLY,
      Tasker::Constants::WorkflowStepStatuses::ERROR
    ].include?(current_state)
      step.state_machine.transition_to!(:in_progress)
    end

    step.update_columns(in_process: true)
    step
  end

  # Force step to in_progress bypassing guards (for testing edge cases)
  # This simulates scenarios where a step gets into in_progress state outside normal workflow
  def force_step_in_progress(step)
    # Directly create transition without going through state machine guards
    # This is for testing edge cases where steps are in unexpected states
    max_sort_key = step.workflow_step_transitions.maximum(:sort_key) || 0

    create(:workflow_step_transition,
           workflow_step: step,
           to_state: Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS,
           sort_key: max_sort_key + 1,
           most_recent: true)

    # Update previous transition to not be most recent
    step.workflow_step_transitions.where(most_recent: true)
        .where.not(id: step.workflow_step_transitions.last.id)
        .update_all(most_recent: false)

    # Update the step columns to match
    step.update_columns(in_process: true)
    step
  end

  # Set step to cancelled (replacement for step.update!({ status: CANCELLED }))
  def set_step_cancelled(step)
    # Handle case where step might not have any transitions yet
    max_sort_key = step.workflow_step_transitions.maximum(:sort_key) || 0

    # Transition to cancelled state
    create(:workflow_step_transition,
           workflow_step: step,
           to_state: Tasker::Constants::WorkflowStepStatuses::CANCELLED,
           sort_key: max_sort_key + 1,
           most_recent: true)

    # Update previous transition to not be most recent
    step.workflow_step_transitions.where(most_recent: true)
        .where.not(id: step.workflow_step_transitions.last.id)
        .update_all(most_recent: false)

    step
  end

  # Set step to backoff state (replacement for step.update!({ backoff_request_seconds: 30, last_attempted_at: Time.zone.now }))
  def set_step_in_backoff(step, backoff_seconds = 30)
    step.update_columns(
      backoff_request_seconds: backoff_seconds,
      last_attempted_at: Time.zone.now
    )
    step
  end

  # Set step to error with max retries (replacement for complex error setup)
  def set_step_to_max_retries_error(step)
    step.state_machine.transition_to!(:in_progress)
    step.state_machine.transition_to!(:error)
    step.update_columns(
      attempts: step.retry_limit + 1,
      results: { error: 'Max retries reached' }
    )
    step
  end

  # Set step to error state with custom error message (for API integration testing)
  def set_step_to_error(step, error_message = 'Test error')
    step.state_machine.transition_to!(:in_progress) if step.state_machine.current_state == 'pending'
    step.state_machine.transition_to!(:error)
    step.update_columns(
      processed: false,
      results: { error: error_message }
    )
    step
  end

  # Get sequence (temporary compatibility method for tests still using task_handler.get_sequence)
  def get_sequence_for_task(task)
    # Create a simple struct that provides access to steps and find_step_by_name
    # This maintains compatibility while we migrate away from sequence objects
    SequenceStruct.new(
      task.workflow_steps.includes(:named_step),
      task
    )
  end

  # Get viable steps (replacement for WorkflowStep.get_viable_steps)
  def get_viable_steps_for_task(task)
    sequence = get_sequence_for_task(task)
    Tasker::WorkflowStep.get_viable_steps(task, sequence)
  end

  # Register task handler (replacement for factory.register in tests)
  def register_task_handler(task_name, handler_class)
    factory = Tasker::HandlerFactory.instance
    factory.register(task_name, handler_class)
  end

  # Create task handler with connection stubbing (for API integration tests)
  def create_api_task_handler_with_connection(handler_class, connection)
    handler = handler_class.new

    # Override get_step_handler to inject the mocked connection
    original_get_step_handler = handler.method(:get_step_handler)
    handler.define_singleton_method(:get_step_handler) do |step|
      step_handler = original_get_step_handler.call(step)

      # For API step handlers, override the connection that was built during initialization
      step_handler.instance_variable_set(:@connection, connection) if step_handler.is_a?(Tasker::StepHandler::Api)

      step_handler
    end

    handler
  end

  # Create a dummy task following the real TaskRequest initialization pattern
  # This mirrors how tasks are actually created in production but allows factory overrides
  def create_dummy_task_via_request(options = {})
    # Extract factory options vs task_request options
    factory_options = options.extract!(:with_dependencies, :step_states, :complete_steps, :bypass_steps)

    # Register the DummyTask handler first (essential for real workflow)
    register_task_handler(DummyTask::TASK_REGISTRY_NAME, DummyTask)

    # Create a TaskRequest following the real-world pattern
    task_request_params = {
      name: DummyTask::TASK_REGISTRY_NAME,
      initiator: 'test@example.com',
      reason: 'testing orchestration',
      source_system: 'test-system',
      context: { dummy: true },
      tags: %w[dummy testing orchestration],
      bypass_steps: factory_options[:bypass_steps] || []
    }.merge(options)

    task_request = Tasker::Types::TaskRequest.new(task_request_params)

    # Create task using the real initialization flow
    task = Tasker::Task.create_with_defaults!(task_request)

    # Let the task handler establish steps and dependencies (real-world pattern)
    if factory_options.fetch(:with_dependencies, true)
      task_handler = Tasker::HandlerFactory.instance.get(DummyTask::TASK_REGISTRY_NAME)

      # This follows the real workflow initialization pattern:
      # 1. Get step templates from the handler
      # 2. Get steps for the task (creates workflow steps if they don't exist)
      # 3. Establish dependencies and defaults
      step_templates = task_handler.step_templates
      steps = Tasker::WorkflowStep.get_steps_for_task(task, step_templates)
      task_handler.establish_step_dependencies_and_defaults(task, steps)

      # Reload task to get the created workflow steps
      task.reload

      # Handle step state configuration if specified
      step_states = factory_options[:step_states] || :pending
      complete_steps = factory_options[:complete_steps] || []

      case step_states
      when :pending
        # Steps are already in pending state by default - no action needed
        nil
      when :some_complete
        # Complete the first two steps (step-one and step-two)
        complete_steps = [DummyTask::STEP_ONE, DummyTask::STEP_TWO] if complete_steps.empty?
      end

      # Complete specified steps using state machine transitions
      complete_steps.each do |step_name|
        step = task.workflow_steps.joins(:named_step).find_by(named_step: { name: step_name })
        next unless step

        step.state_machine.transition_to!(:in_progress)
        step.state_machine.transition_to!(:complete)
        step.update_columns(
          processed: true,
          processed_at: Time.current,
          results: { dummy: true, step_name: step_name }
        )
      end
    end

    task
  end

  # Create a dummy task specifically for orchestration testing
  # This ensures the task is in the proper pending state for event-driven processing
  def create_dummy_task_for_orchestration_via_request(options = {})
    # Force steps to pending state for orchestration testing
    options = options.merge(
      step_states: :pending,
      complete_steps: [] # No pre-completed steps for orchestration testing
    )

    create_dummy_task_via_request(options)
  end

  private

  # Complete any dependencies for a step to ensure state machine guards pass
  def complete_step_dependencies(step)
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
      unless completion_states.include?(parent_status)
        Rails.logger.debug do
          "Test Helper: Completing parent step #{parent.workflow_step_id} (currently #{parent_status}) to satisfy dependency for step #{step.workflow_step_id}"
        end
        complete_step_via_state_machine(parent)
      else
        Rails.logger.debug do
          "Test Helper: Parent step #{parent.workflow_step_id} already complete (#{parent_status}) - skipping"
        end
      end
    end
  end

  public
end

# Include in RSpec configuration
RSpec.configure do |config|
  config.include FactoryWorkflowHelpers
end
