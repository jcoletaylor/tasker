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

    # Use safe transitions to avoid state machine errors
    # Include IdempotentStateTransitions concern for safe_transition_to
    step.extend(Tasker::Concerns::IdempotentStateTransitions)

    # Get current state - be defensive about state transitions
    current_state = step.state_machine.current_state
    current_state = Tasker::Constants::WorkflowStepStatuses::PENDING if current_state.blank?

    # Only transition if not already complete
    completion_states = [
      Tasker::Constants::WorkflowStepStatuses::COMPLETE,
      Tasker::Constants::WorkflowStepStatuses::RESOLVED_MANUALLY
    ]

    unless completion_states.include?(current_state)
      # Handle error state - must transition to pending first, then in_progress
      if current_state == Tasker::Constants::WorkflowStepStatuses::ERROR
        step.safe_transition_to(step, Tasker::Constants::WorkflowStepStatuses::PENDING)
        current_state = Tasker::Constants::WorkflowStepStatuses::PENDING
      end

      # Transition to in_progress if not already there
      unless current_state == Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS
        step.safe_transition_to(step, Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
      end

      # Transition to complete
      step.safe_transition_to(step, Tasker::Constants::WorkflowStepStatuses::COMPLETE)
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
    StepCompletionService.complete_with_results(step, step_name)
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
    # Reload step to ensure we have the current state (prevents stale state issues)
    step.reload

    # Complete dependencies first to ensure state machine guards pass
    complete_step_dependencies(step)

    # Reload again after dependency completion to ensure we have current state
    step.reload
    current_state = step.state_machine.current_state

    # Only proceed if the step hasn't been completed by dependency resolution
    completion_states = [
      Tasker::Constants::WorkflowStepStatuses::COMPLETE,
      Tasker::Constants::WorkflowStepStatuses::RESOLVED_MANUALLY
    ]

    if completion_states.include?(current_state)
      Rails.logger.warn "Test Helper: Step #{step.workflow_step_id} was completed during dependency resolution - cannot set to error"
      return step
    end

    # Now transition to in_progress if still in pending state
    step.state_machine.transition_to!(:in_progress) if current_state == 'pending'
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
    DummyTaskRequestService.create_with_options(options)
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
      if completion_states.include?(parent_status)
        Rails.logger.debug do
          "Test Helper: Parent step #{parent.workflow_step_id} already complete (#{parent_status}) - skipping"
        end
      else
        Rails.logger.debug do
          "Test Helper: Completing parent step #{parent.workflow_step_id} (currently #{parent_status}) to satisfy dependency for step #{step.workflow_step_id}"
        end
        complete_step_via_state_machine(parent)
      end
    end
  end

  # Service class to handle step completion with results
  # Reduces complexity by organizing completion logic
  class StepCompletionService
    class << self
      # Complete a step with appropriate results based on step name
      #
      # @param step [Tasker::WorkflowStep] The step to complete
      # @param step_name [String] Optional step name override
      # @return [Tasker::WorkflowStep] The completed step
      def complete_with_results(step, step_name = nil)
        step_name ||= step.named_step.name

        # Handle state transition logic
        StateTransitionHandler.handle_completion_transitions(step)

        # Set step-specific results and complete
        results = ResultsGenerator.generate_for_step(step_name)
        finalize_step_completion(step, results)

        step
      end

      private

      # Finalize step completion with results
      #
      # @param step [Tasker::WorkflowStep] The step to complete
      # @param results [Hash] Results to set
      # @return [void]
      def finalize_step_completion(step, results)
        # Ensure step is in in_progress state before transitioning to complete
        current_state = step.state_machine.current_state
        current_state = Tasker::Constants::WorkflowStepStatuses::PENDING if current_state.blank?

        # Only transition to in_progress if not already there or beyond
        unless [
          Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS,
          Tasker::Constants::WorkflowStepStatuses::COMPLETE,
          Tasker::Constants::WorkflowStepStatuses::RESOLVED_MANUALLY
        ].include?(current_state)
          step.state_machine.transition_to!(:in_progress)
        end

        # Now transition to complete (only if not already complete)
        unless [
          Tasker::Constants::WorkflowStepStatuses::COMPLETE,
          Tasker::Constants::WorkflowStepStatuses::RESOLVED_MANUALLY
        ].include?(current_state)
          step.state_machine.transition_to!(:complete)
        end

        step.update_columns(
          processed: true,
          processed_at: Time.current,
          results: results
        )
      end
    end

    # Service class to handle state transitions for step completion
    class StateTransitionHandler
      class << self
        # Handle all necessary state transitions for completion
        #
        # @param step [Tasker::WorkflowStep] The step to transition
        # @return [void]
        def handle_completion_transitions(step)
          current_state = get_current_state(step)

          return if already_completed?(current_state)

          handle_error_state_recovery(step) if error_state?(current_state)
          transition_to_in_progress_if_needed(step, current_state)
        end

        private

        # Get current state with defensive handling
        #
        # @param step [Tasker::WorkflowStep] The step
        # @return [String] Current state
        def get_current_state(step)
          current_state = step.state_machine.current_state
          current_state.presence || Tasker::Constants::WorkflowStepStatuses::PENDING
        end

        # Check if step is already completed
        #
        # @param current_state [String] Current state
        # @return [Boolean] True if already completed
        def already_completed?(current_state)
          completion_states = [
            Tasker::Constants::WorkflowStepStatuses::COMPLETE,
            Tasker::Constants::WorkflowStepStatuses::RESOLVED_MANUALLY
          ]
          completion_states.include?(current_state)
        end

        # Check if step is in error state
        #
        # @param current_state [String] Current state
        # @return [Boolean] True if in error state
        def error_state?(current_state)
          current_state == Tasker::Constants::WorkflowStepStatuses::ERROR
        end

        # Handle recovery from error state
        #
        # @param step [Tasker::WorkflowStep] The step to recover
        # @return [void]
        def handle_error_state_recovery(step)
          step.state_machine.transition_to!(:pending)
        end

        # Transition to in_progress if needed
        #
        # @param step [Tasker::WorkflowStep] The step to transition
        # @param current_state [String] Current state
        # @return [void]
        def transition_to_in_progress_if_needed(step, current_state)
          return if in_progress_or_beyond?(current_state)

          step.state_machine.transition_to!(:in_progress)
        end

        # Check if step is in progress or beyond
        #
        # @param current_state [String] Current state
        # @return [Boolean] True if in progress or beyond
        def in_progress_or_beyond?(current_state)
          advanced_states = [
            Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS,
            Tasker::Constants::WorkflowStepStatuses::COMPLETE,
            Tasker::Constants::WorkflowStepStatuses::RESOLVED_MANUALLY
          ]
          advanced_states.include?(current_state)
        end
      end
    end

    # Service class to generate results based on step names
    class ResultsGenerator
      class << self
        # Generate appropriate results for a step based on its name
        #
        # @param step_name [String] The name of the step
        # @return [Hash] Generated results
        def generate_for_step(step_name)
          case step_name
          when 'fetch_cart'
            generate_cart_results
          when 'fetch_products'
            generate_products_results
          when 'validate_products'
            generate_validation_results
          when 'create_order'
            generate_order_results
          when 'publish_event'
            generate_publish_results
          else
            generate_default_results
          end
        end

        private

        # Generate cart fetch results
        #
        # @return [Hash] Cart results
        def generate_cart_results
          { cart: { id: 1, items: [{ product_id: 1, quantity: 2 }] } }
        end

        # Generate products fetch results
        #
        # @return [Hash] Products results
        def generate_products_results
          { products: [{ id: 1, name: 'Test Product', in_stock: true }] }
        end

        # Generate validation results
        #
        # @return [Hash] Validation results
        def generate_validation_results
          { valid_products: [{ id: 1, validated: true }] }
        end

        # Generate order creation results
        #
        # @return [Hash] Order results
        def generate_order_results
          { order_id: SecureRandom.uuid }
        end

        # Generate publish event results
        #
        # @return [Hash] Publish results
        def generate_publish_results
          { published: true, publish_results: { status: 'placed_pending_fulfillment' } }
        end

        # Generate default results
        #
        # @return [Hash] Default results
        def generate_default_results
          { dummy: true, other: true }
        end
      end
    end
  end

  # Service class to handle dummy task creation via request pattern
  # Reduces complexity by organizing task creation logic
  class DummyTaskRequestService
    class << self
      # Create a dummy task with specified options
      #
      # @param options [Hash] Task creation options
      # @return [Tasker::Task] Created task
      def create_with_options(options = {})
        factory_options = options.extract!(:with_dependencies, :step_states, :complete_steps, :bypass_steps)

        # Register handler and create task
        register_dummy_task_handler
        task = create_task_from_request(options, factory_options[:bypass_steps])

        # Set up workflow dependencies if requested
        setup_workflow_dependencies(task, factory_options) if factory_options.fetch(:with_dependencies, true)

        task
      end

      private

      # Register the DummyTask handler
      #
      # @return [void]
      def register_dummy_task_handler
        factory = Tasker::HandlerFactory.instance
        factory.register(DummyTask::TASK_REGISTRY_NAME, DummyTask)
      end

      # Create task from request parameters
      #
      # @param options [Hash] Task creation options
      # @param bypass_steps [Array] Steps to bypass
      # @return [Tasker::Task] Created task
      def create_task_from_request(options, bypass_steps)
        task_request_params = build_task_request_params(options, bypass_steps)
        task_request = Tasker::Types::TaskRequest.new(task_request_params)
        Tasker::Task.create_with_defaults!(task_request)
      end

      # Build task request parameters
      #
      # @param options [Hash] User-provided options
      # @param bypass_steps [Array] Steps to bypass
      # @return [Hash] Task request parameters
      def build_task_request_params(options, bypass_steps)
        {
          name: DummyTask::TASK_REGISTRY_NAME,
          initiator: 'test@example.com',
          reason: 'testing orchestration',
          source_system: 'test-system',
          context: { dummy: true },
          tags: %w[dummy testing orchestration],
          bypass_steps: bypass_steps || []
        }.merge(options)
      end

      # Set up workflow dependencies for the task
      #
      # @param task [Tasker::Task] The task to set up
      # @param factory_options [Hash] Factory configuration options
      # @return [void]
      def setup_workflow_dependencies(task, factory_options)
        WorkflowSetupService.configure_workflow(task, factory_options)
      end
    end

    # Service class to handle workflow setup and step configuration
    class WorkflowSetupService
      class << self
        # Configure workflow for the task
        #
        # @param task [Tasker::Task] The task to configure
        # @param factory_options [Hash] Factory configuration options
        # @return [void]
        def configure_workflow(task, factory_options)
          initialize_workflow_steps(task)
          configure_step_states(task, factory_options)
        end

        private

        # Initialize workflow steps using real-world pattern
        #
        # @param task [Tasker::Task] The task to initialize
        # @return [void]
        def initialize_workflow_steps(task)
          task_handler = Tasker::HandlerFactory.instance.get(DummyTask::TASK_REGISTRY_NAME)

          # Follow real workflow initialization pattern
          step_templates = task_handler.step_templates
          steps = Tasker::WorkflowStep.get_steps_for_task(task, step_templates)
          task_handler.establish_step_dependencies_and_defaults(task, steps)

          task.reload
        end

        # Configure step states based on factory options
        #
        # @param task [Tasker::Task] The task to configure
        # @param factory_options [Hash] Factory configuration options
        # @return [void]
        def configure_step_states(task, factory_options)
          step_states = factory_options[:step_states] || :pending
          complete_steps = determine_steps_to_complete(step_states, factory_options[:complete_steps])

          complete_specified_steps(task, complete_steps)
        end

        # Determine which steps to complete based on configuration
        #
        # @param step_states [Symbol] Step states configuration
        # @param explicit_complete_steps [Array] Explicitly specified steps to complete
        # @return [Array] Steps to complete
        def determine_steps_to_complete(step_states, explicit_complete_steps)
          return explicit_complete_steps || [] unless step_states == :some_complete

          # Default for :some_complete - complete first two steps
          explicit_complete_steps.presence || [DummyTask::STEP_ONE, DummyTask::STEP_TWO]
        end

        # Complete specified steps using state machine transitions
        #
        # @param task [Tasker::Task] The task containing steps
        # @param complete_steps [Array] Step names to complete
        # @return [void]
        def complete_specified_steps(task, complete_steps)
          complete_steps.each do |step_name|
            step = task.workflow_steps.joins(:named_step).find_by(named_step: { name: step_name })
            next unless step

            complete_individual_step(step, step_name)
          end
        end

        # Complete an individual step with transitions and results
        #
        # @param step [Tasker::WorkflowStep] The step to complete
        # @param step_name [String] The step name
        # @return [void]
        def complete_individual_step(step, step_name)
          step.state_machine.transition_to!(:in_progress)
          step.state_machine.transition_to!(:complete)
          step.update_columns(
            processed: true,
            processed_at: Time.current,
            results: { dummy: true, step_name: step_name }
          )
        end
      end
    end
  end
end

# Include in RSpec configuration
RSpec.configure do |config|
  config.include FactoryWorkflowHelpers
end
