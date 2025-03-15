# typed: false
# frozen_string_literal: true

require 'json-schema'

module Tasker
  module TaskHandler
    module InstanceMethods
      extend T::Sig
      # typed: true
      sig { params(task_request: TaskRequest).returns(Task) }
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
      sig { params(task: Task).returns(StepSequence) }
      def get_sequence(task)
        steps = Tasker::WorkflowStep.get_steps_for_task(task, step_templates)
        establish_step_dependencies_and_defaults(task, steps)
        Tasker::StepSequence.new(steps: steps)
      end

      # typed: true
      sig { params(task: Task).returns(T::Boolean) }
      def start_task(task)
        raise(Tasker::ProceduralError, "task already complete for task #{task.task_id}") if task.complete

        unless task.status == Tasker::Constants::TaskStatuses::PENDING
          raise(Tasker::ProceduralError,
                "task is not pending for task #{task.task_id}, status is #{task.status}")
        end

        task.update!({ status: Tasker::Constants::TaskStatuses::IN_PROGRESS })
      end

      # typed: true
      sig { params(task: Task).void }
      def handle(task)
        start_task(task)
        sequence = get_sequence(task)
        viable_steps = Tasker::WorkflowStep.get_viable_steps(task, sequence)
        steps = handle_viable_steps(task, sequence, viable_steps)
        # get sequence again, updated
        sequence = get_sequence(task)
        more_viable_steps = Tasker::WorkflowStep.get_viable_steps(task, sequence)
        if more_viable_steps.length.positive?
          task.update!({ status: Tasker::Constants::TaskStatuses::PENDING })
          # if there are more viable steps that we can handle now
          # that we are not waiting on, then just recursively call handle again
          return handle(task)
        end
        finalize(task, sequence, steps)
      end

      # typed: true
      sig { params(task: Task, sequence: StepSequence, step: WorkflowStep).returns(WorkflowStep) }
      def handle_one_step(task, sequence, step)
        handler = get_step_handler(step)
        attempts = step.attempts || 0
        begin
          handler.handle(task, sequence, step)
          step.processed = true
          step.processed_at = Time.zone.now
          step.status = Tasker::Constants::WorkflowStepStatuses::COMPLETE
        rescue StandardError => e
          step.processed = false
          step.processed_at = nil
          step.status = Tasker::Constants::WorkflowStepStatuses::ERROR
          step.results = { error: e.to_s }
        end
        step.attempts = attempts + 1
        step.last_attempted_at = Time.zone.now
        step.save!
        step
      end

      # typed: true
      sig { params(task: Task, sequence: StepSequence, steps: T::Array[WorkflowStep]).returns(T::Array[WorkflowStep]) }
      def handle_viable_steps(task, sequence, steps)
        steps.each do |step|
          handle_one_step(task, sequence, step)
        end
        # we can update annotations in every pass
        update_annotations(task, sequence, steps)
        steps
      end

      # we are finalizing whether a task is complete
      # whether it is in error, or whether we can still retry it
      # or whether no errors exist but if we should re-enqueue
      # if there are still valid workable steps

      # typed: true
      sig { params(task: Task, sequence: StepSequence, steps: T::Array[WorkflowStep]).void }
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
      sig { params(task: Task, sequence: StepSequence, steps: T::Array[WorkflowStep]).returns(T::Boolean) }
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

        step_handler_class_map[step.name].to_s.camelize.constantize.new
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
      sig { params(task: Task, sequence: StepSequence, steps: T::Array[WorkflowStep]).void }
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
