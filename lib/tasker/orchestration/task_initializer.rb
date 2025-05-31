# frozen_string_literal: true

require_relative '../concerns/idempotent_state_transitions'
require 'tasker/events/event_payload_builder'

module Tasker
  module Orchestration
    # TaskInitializer handles task creation and initialization logic
    #
    # This component is responsible for:
    # - Creating tasks from TaskRequest objects
    # - Validating task context against schemas
    # - Starting task execution (transitioning to in_progress)
    # - Enqueuing tasks for processing
    class TaskInitializer
      include Tasker::Concerns::IdempotentStateTransitions

      class << self
        # Initialize a new task from a task request
        #
        # Creates a task record, validates the context against the schema,
        # and enqueues the task for processing.
        #
        # @param task_request [Tasker::Types::TaskRequest] The task request
        # @param task_handler [Object] The task handler instance for schema validation
        # @return [Tasker::Task] The created task
        def initialize_task!(task_request, task_handler)
          new.initialize_task!(task_request, task_handler)
        end

        # Start a task's execution
        #
        # Updates the task status to IN_PROGRESS and fires the appropriate event.
        #
        # @param task [Tasker::Task] The task to start
        # @return [Boolean] True if the task was started successfully
        def start_task!(task)
          new.start_task!(task)
        end
      end

      # Initialize a new task from a task request
      #
      # @param task_request [Tasker::Types::TaskRequest] The task request
      # @param task_handler [Object] The task handler instance for schema validation
      # @return [Tasker::Task] The created task
      def initialize_task!(task_request, task_handler)
        task = nil
        context_errors = validate_context_with_handler(task_request.context, task_handler)

        if context_errors.length.positive?
          task = Tasker::Task.from_task_request(task_request)
          context_errors.each do |error|
            task.errors.add(:context, error)
          end

          Tasker::LifecycleEvents.fire(
            Tasker::LifecycleEvents::Events::Task::INITIALIZE,
            { task_name: task_request.name, status: 'error', errors: context_errors }
          )
          return task
        end

        Tasker::Task.transaction do
          task = Tasker::Task.create_with_defaults!(task_request)
          # Get sequence and establish dependencies
          StepSequenceFactory.create_sequence_for_task!(task, task_handler)
        end

        Tasker::LifecycleEvents.fire(
          Tasker::LifecycleEvents::Events::Task::INITIALIZE,
          { task_id: task.task_id, task_name: task.name, status: 'success' }
        )

        enqueue_task(task)
        task
      end

      # Start a task's execution
      #
      # @param task [Tasker::Task] The task to start
      # @return [Boolean] True if the task was started successfully
      def start_task!(task)
        raise(Tasker::ProceduralError, "task already complete for task #{task.task_id}") if task.complete

        unless task.status == Tasker::Constants::TaskStatuses::PENDING
          raise(Tasker::ProceduralError,
                "task is not pending for task #{task.task_id}, status is #{task.status}")
        end

        task.context = ActiveSupport::HashWithIndifferentAccess.new(task.context)

        # Use state machine to transition task to in_progress
        transition_result = safe_transition_to(task, Tasker::Constants::TaskStatuses::IN_PROGRESS)

        unless transition_result
          Rails.logger.warn("TaskInitializer: Failed to transition task #{task.task_id} to in_progress")
          return false
        end

        Tasker::LifecycleEvents.fire(
          Tasker::LifecycleEvents::Events::Task::START,
          { task_id: task.task_id, task_name: task.name, task_context: task.context }
        )

        true
      end

      private

      # Validate a task context against the handler's schema
      #
      # @param context [Hash] The context to validate
      # @param task_handler [Object] The task handler with schema
      # @return [Array<String>] Validation errors, if any
      def validate_context_with_handler(context, task_handler)
        return [] unless task_handler.respond_to?(:schema) && task_handler.schema

        data = context.to_hash.deep_symbolize_keys
        JSON::Validator.fully_validate(task_handler.schema, data, strict: true, insert_defaults: true)
      end

      # Enqueue a task for processing
      #
      # @param task [Tasker::Task] The task to enqueue
      def enqueue_task(task)
        payload = Tasker::Events::EventPayloadBuilder.build_task_payload(
          task,
          event_type: :enqueue,
          additional_context: {
            task_context: task.context
          }
        )

        Tasker::LifecycleEvents.fire(
          Tasker::Constants::ObservabilityEvents::Task::ENQUEUE,
          payload
        )

        Tasker::TaskRunnerJob.perform_later(task.task_id)
      end
    end
  end
end
