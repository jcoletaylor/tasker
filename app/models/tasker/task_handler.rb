# typed: false
# frozen_string_literal: true

require 'json-schema'

module Tasker
  module TaskHandler
    extend T::Sig
    attr_accessor :step_handler_class_map

    def self.included(klass)
      klass.extend(ClassMethods)
    end

    module ClassMethods
      class StepTemplateDefiner
        attr_reader :step_templates, :klass

        def initialize(klass)
          @klass = klass
          @step_templates = []
        end

        def define(**kwargs)
          dependent_system = kwargs.fetch(:dependent_system, Tasker::Constants::UNKNOWN)
          name = kwargs.fetch(:name)
          handler_class = kwargs.fetch(:handler_class)
          description = kwargs.fetch(:description, name)
          default_retryable = kwargs.fetch(:default_retryable, true)
          default_retry_limit = kwargs.fetch(:default_retry_limit, 3)
          skippable = kwargs.fetch(:skippable, false)
          depends_on_step = kwargs.fetch(:depends_on_step, nil)

          @step_templates << Tasker::StepTemplate.new(
            dependent_system: dependent_system,
            name: name,
            description: description,
            default_retryable: default_retryable,
            default_retry_limit: default_retry_limit,
            skippable: skippable,
            handler_class: handler_class,
            depends_on_step: depends_on_step
          )
        end
      end

      def define_step_templates
        definer = StepTemplateDefiner.new(self)
        yield definer
        definer.klass.define_method :step_templates do
          definer.step_templates
        end
      end
    end

    def initialize
      # NOTE: this relies on super being called
      # or classes where this is included calling
      # the register methods themselves
      register_step_handler_classes
    end

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
      raise Tasker::ProceduralError, "task already complete for task #{task.task_id}" if task.complete

      raise Tasker::ProceduralError, "task is not pending for task #{task.task_id}, status is #{task.status}" unless task.status == Tasker::Constants::TaskStatuses::PENDING

      task.update({ status: Tasker::Constants::TaskStatuses::IN_PROGRESS })
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
        task.update({ status: Tasker::Constants::TaskStatuses::PENDING })
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

    # this is a long method, there's no real way around it
    # we are finalizing whether a task is complete
    # whether it is in error, or whether we can still retry it
    # or whether no errors exist but if we should re-enqueue
    # if there are still valid workable steps
    # we could break it down into components, but I think it may be
    # harder to reason about

    # typed: true
    sig { params(task: Task, sequence: StepSequence, steps: T::Array[WorkflowStep]).void }
    def finalize(task, sequence, steps)
      # how many steps in this round are in an error state before, and based on
      # being processed in this round of handling, is it still in an error state
      error_steps = get_error_steps(steps, sequence)
      # if there are no steps in error still, then move on to the rest of the checks
      # if there are steps in error still, then we need to see if we have tried them
      # too many times - if we have, we need to mark the whole task as in error
      # if we have not, then we need to re-enqueue the task

      if error_steps.length.positive?
        too_many_attempts_steps = []
        error_steps.each do |err_step|
          too_many_attempts_steps << err_step if err_step.attempts.positive? && !err_step.retryable
          too_many_attempts_steps << err_step if err_step.attempts >= err_step.retry_limit
        end
        if too_many_attempts_steps.length.positive?
          task.update({ status: Tasker::Constants::TaskStatuses::ERROR })
          return
        end
        task.update({ status: Tasker::Constants::TaskStatuses::PENDING })
        enqueue_task(task)
        return
      end
      # determine which states were incomplete for the whole sequence before this round
      prior_incomplete_steps = []
      sequence.steps.each do |step|
        prior_incomplete_steps << step unless Tasker::Constants::VALID_STEP_COMPLETION_STATES.include?(step.status)
      end
      # if nothing was incomplete, set the task to complete and save, and return
      if prior_incomplete_steps.length.zero?
        task.update({ status: Tasker::Constants::TaskStatuses::COMPLETE })
        return
      end
      # the steps that are passed into finalize are not the whole sequence
      # just what has been worked on in this pass, so we need to see what completed
      # in a valid state, and what has still to be done
      this_pass_complete_steps = []
      steps.each do |step|
        this_pass_complete_steps << step if Tasker::Constants::VALID_STEP_COMPLETION_STATES.include?(step.status)
      end
      this_pass_complete_step_ids = this_pass_complete_steps.map(&:workflow_step_id)
      # what was incomplete from the prior pass that is still incopmlete now
      still_incomplete_steps = []
      prior_incomplete_steps.each do |step|
        still_incomplete_steps << step unless this_pass_complete_step_ids.include?(step.workflow_step_id)
      end
      # if nothing is still incomplete after this pass
      # mark the task complete, update it, and return
      if still_incomplete_steps.length.zero?
        task.update({ status: Tasker::Constants::TaskStatuses::COMPLETE })
        return
      end
      # what is still working but in a valid, retryable state
      still_working_steps = []
      still_incomplete_steps.each do |step|
        still_working_steps << step if Tasker::Constants::VALID_STEP_STILL_WORKING_STATES.include?(step.status)
      end
      # if we have steps that still need to be completed and in valid states
      # set the status of the task back to pending, update it,
      # and re-enqueue the task for processing
      if still_working_steps.length.positive?
        task.update({ status: Tasker::Constants::TaskStatuses::PENDING })
        enqueue_task(task)
        return
      end
      # if we reach the end and have not re-enqueued the task
      # then we mark it complete since none of the above proved true
      task.update({ status: Tasker::Constants::TaskStatuses::COMPLETE })
      return
    end

    def register_step_handler_classes
      self.step_handler_class_map = {}
      step_templates.each do |template|
        step_handler_class_map[template.name] = template.handler_class.to_s
      end
    end

    def get_step_handler(step)
      raise Tasker::ProceduralError, "No registered class for #{step.name}" unless step_handler_class_map[step.name]

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
      errors = JSON::Validator.fully_validate(schema, data, strict: true, insert_defaults: true)
      errors
    end
  end
end
