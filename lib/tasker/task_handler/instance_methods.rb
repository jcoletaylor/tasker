# typed: false
# frozen_string_literal: true

require 'json-schema'

module Tasker
  module TaskHandler
    module InstanceMethods
      extend T::Sig
      # typed: true
      sig { params(task_request: Tasker::Types::TaskRequest).returns(Task) }
      def initialize_task!(task_request)
        task = nil
        context_errors = validate_context(task_request.context)
        if context_errors.length.positive?
          task = Tasker::Task.from_task_request(task_request)
          context_errors.each do |error|
            task.errors.add(:context, error)
          end
          return task
        end
        Tasker::Task.transaction do
          task = Tasker::Task.create_with_defaults!(task_request)
          get_sequence(task)
        end
        enqueue_task(task)
        task
      end

      # typed: true
      sig { params(task: Task).returns(Tasker::Types::StepSequence) }
      def get_sequence(task)
        steps = Tasker::WorkflowStep.get_steps_for_task(task, step_templates)
        establish_step_dependencies_and_defaults(task, steps)
        Tasker::Types::StepSequence.new(steps: steps)
      end

      # typed: true
      sig { params(task: Task).returns(T::Boolean) }
      def start_task(task)
        raise(Tasker::ProceduralError, "task already complete for task #{task.task_id}") if task.complete

        unless task.status == Tasker::Constants::TaskStatuses::PENDING
          raise(Tasker::ProceduralError,
                "task is not pending for task #{task.task_id}, status is #{task.status}")
        end

        task.context = ActiveSupport::HashWithIndifferentAccess.new(task.context)

        task.update!({ status: Tasker::Constants::TaskStatuses::IN_PROGRESS })
      end

      # typed: true
      sig { params(task: Task).void }
      def handle(task)
        start_task(task)

        # Process steps recursively until no more viable steps are found
        all_processed_steps = []

        loop do
          # Get the latest sequence with up-to-date step statuses
          task.reload
          sequence = get_sequence(task)

          # Find viable steps according to DAG traversal
          # Force a fresh load of all steps, including children of completed steps
          viable_steps = find_viable_steps_directly(task, sequence)

          # If no viable steps found, we're done
          break if viable_steps.empty?

          # Process the viable steps
          processed_in_this_round = handle_viable_steps(task, sequence, viable_steps)
          all_processed_steps.concat(processed_in_this_round)

          # Check if any errors occurred that would block further progress
          break if blocked_by_errors?(task, sequence, processed_in_this_round)
        end

        # Get final sequence after all processing
        final_sequence = get_sequence(task)

        # Finalize the task
        finalize(task, final_sequence, all_processed_steps)
      end

      # Direct method to find viable steps, properly checking latest DB state
      def find_viable_steps_directly(task, sequence)
        unfinished_steps = sequence.steps.reject { |step| step.processed || step.in_process }

        viable_steps = []
        unfinished_steps.each do |step|
          # Reload to get latest status
          fresh_step = Tasker::WorkflowStep.find(step.workflow_step_id)

          # Skip if step is now processed or in process
          next if fresh_step.processed || fresh_step.in_process

          # Check if step is viable with latest DB state
          viable_steps << fresh_step if Tasker::WorkflowStep.is_step_viable?(fresh_step, task)
        end

        viable_steps
      end

      # typed: true
      sig { params(task: Task, sequence: Tasker::Types::StepSequence, step: WorkflowStep).returns(WorkflowStep) }
      def handle_one_step(task, sequence, step)
        handler = get_step_handler(step)
        step.attempts ||= 0
        begin
          handler.handle(task, sequence, step)
          step.processed = true
          step.processed_at = Time.zone.now
          step.status = Tasker::Constants::WorkflowStepStatuses::COMPLETE
        rescue StandardError => e
          step.processed = false
          step.processed_at = nil
          step.status = Tasker::Constants::WorkflowStepStatuses::ERROR
          step.results ||= {}
          step.results = step.results.merge(error: e.to_s, backtrace: e.backtrace.join("\n"))
        end
        step.attempts += 1
        step.last_attempted_at = Time.zone.now
        step.save!
        step
      end

      # typed: true
      sig do
        params(task: Task, sequence: Tasker::Types::StepSequence,
               steps: T::Array[WorkflowStep]).returns(T::Array[WorkflowStep])
      end
      def handle_viable_steps(task, sequence, steps)
        # If concurrent processing is not enabled, process steps sequentially
        unless respond_to?(:use_concurrent_processing?) && use_concurrent_processing?
          return handle_viable_steps_sequentially(task, sequence, steps)
        end

        # Create an array of futures and processed steps
        futures = []
        processed_steps = Concurrent::Array.new

        # Create a future for each step
        steps.each do |step|
          # Use Concurrent::Future to process each step asynchronously
          future = Concurrent::Future.execute do
            handle_one_step(task, sequence, step)
          end

          futures << future
        end

        # Wait for all futures to complete
        futures.each do |future|
          # Wait for the future to complete (with a reasonable timeout)
          begin
            # 30 second timeout to prevent indefinite hanging
            result = future.value(30)
            processed_steps << result if result
          rescue => e
            Rails.logger.error("Error processing step concurrently: #{e.message}")
          end
        end

        # Update annotations for this batch
        update_annotations(task, sequence, processed_steps)

        processed_steps.to_a
      end

      # Process steps sequentially
      # typed: true
      sig do
        params(task: Task, sequence: Tasker::Types::StepSequence,
               steps: T::Array[WorkflowStep]).returns(T::Array[WorkflowStep])
      end
      def handle_viable_steps_sequentially(task, sequence, steps)
        processed_steps = []

        # Process each step one at a time
        steps.each do |step|
          processed_step = handle_one_step(task, sequence, step)
          processed_steps << processed_step
        end

        # Update annotations for this batch
        update_annotations(task, sequence, processed_steps)

        processed_steps
      end

      # we are finalizing whether a task is complete
      # whether it is in error, or whether we can still retry it
      # or whether no errors exist but if we should re-enqueue
      # if there are still valid workable steps

      # typed: true
      sig { params(task: Task, sequence: Tasker::Types::StepSequence, steps: T::Array[WorkflowStep]).void }
      def finalize(task, sequence, steps)
        return if blocked_by_errors?(task, sequence, steps)

        step_group = StepGroup.build(task, sequence, steps)

        if step_group.complete?
          task.update!({ status: Tasker::Constants::TaskStatuses::COMPLETE })
          return
        end

        # if we have steps that still need to be completed and in valid states
        # set the status of the task back to pending, update it,
        # and re-enqueue the task for processing
        if step_group.pending?
          task.update!({ status: Tasker::Constants::TaskStatuses::PENDING })
          enqueue_task(task)
          return
        end
        # if we reach the end and have not re-enqueued the task
        # then we mark it complete since none of the above proved true
        task.update!({ status: Tasker::Constants::TaskStatuses::COMPLETE })
        nil
      end

      # typed: true
      sig { params(error_steps: T::Array[WorkflowStep]).returns(T::Boolean) }
      def too_many_attempts?(error_steps)
        too_many_attempts_steps = []
        error_steps.each do |err_step|
          too_many_attempts_steps << err_step if err_step.attempts.positive? && !err_step.retryable
          too_many_attempts_steps << err_step if err_step.attempts >= err_step.retry_limit
        end
        too_many_attempts_steps.length.positive?
      end

      # typed: true
      sig do
        params(task: Task, sequence: Tasker::Types::StepSequence, steps: T::Array[WorkflowStep]).returns(T::Boolean)
      end
      def blocked_by_errors?(task, sequence, steps)
        # how many steps in this round are in an error state before, and based on
        # being processed in this round of handling, is it still in an error state
        error_steps = get_error_steps(steps, sequence)
        # if there are no steps in error still, then move on to the rest of the checks
        # if there are steps in error still, then we need to see if we have tried them
        # too many times - if we have, we need to mark the whole task as in error
        # if we have not, then we need to re-enqueue the task

        if error_steps.length.positive?
          if too_many_attempts?(error_steps)
            task.update!({ status: Tasker::Constants::TaskStatuses::ERROR })
            return true
          end
          task.update!({ status: Tasker::Constants::TaskStatuses::PENDING })
          enqueue_task(task)
          return true
        end
        false
      end

      def get_step_handler(step)
        raise(Tasker::ProceduralError, "No registered class for #{step.name}") unless step_handler_class_map[step.name]

        handler_config = step_handler_config_map[step.name]
        handler_class = step_handler_class_map[step.name].to_s.camelize.constantize

        return handler_class.new if handler_config.nil?

        handler_class.new(config: handler_config)
      end

      def get_error_steps(steps, sequence)
        error_steps = []
        sequence.steps.each do |step|
          # if in the original sequence this was an error
          # we need to see if the updated steps are still in error
          next unless step.status == Tasker::Constants::WorkflowStepStatuses::ERROR

          processed_step =
            steps.find do |s|
              s.workflow_step_id == step.workflow_step_id
            end
          # no updated step was found to change our mind
          # about whether it was in error before, so true, still in error
          if processed_step.nil?
            error_steps << step
            next
          end

          # was the processed step in error still
          error_steps << step if processed_step.status == Tasker::Constants::WorkflowStepStatuses::ERROR
        end
        error_steps
      end

      # typed: true
      sig { params(task: Task).void }
      def enqueue_task(task)
        Tasker::TaskRunnerJob.perform_async(task.task_id)
      end

      # override in implementing class
      # typed: true
      sig { params(task: Task, steps: T::Array[WorkflowStep]).void }
      def establish_step_dependencies_and_defaults(task, steps); end

      # override in implementing class
      # typed: true
      sig { params(task: Task, sequence: Tasker::Types::StepSequence, steps: T::Array[WorkflowStep]).void }
      def update_annotations(task, sequence, steps); end

      # override in implementing class
      def schema
        nil
      end

      def validate_context(context)
        return [] unless schema

        data = context.to_hash.deep_symbolize_keys
        JSON::Validator.fully_validate(schema, data, strict: true, insert_defaults: true)
      end
    end
  end
end
