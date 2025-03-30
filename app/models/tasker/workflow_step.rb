# typed: false
# frozen_string_literal: true

# == Schema Information
#
# Table name: workflow_steps
#
#  attempts                :integer
#  backoff_request_seconds :integer
#  in_process              :boolean          default(FALSE), not null
#  inputs                  :jsonb
#  last_attempted_at       :datetime
#  processed               :boolean          default(FALSE), not null
#  processed_at            :datetime
#  results                 :jsonb
#  retry_limit             :integer          default(3)
#  retryable               :boolean          default(TRUE), not null
#  skippable               :boolean          default(FALSE), not null
#  status                  :string(64)       not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  depends_on_step_id      :bigint
#  named_step_id           :integer          not null
#  task_id                 :bigint           not null
#  workflow_step_id        :bigint           not null, primary key
#
# Indexes
#
#  workflow_steps_depends_on_step_id_index  (depends_on_step_id)
#  workflow_steps_last_attempted_at_index   (last_attempted_at)
#  workflow_steps_named_step_id_index       (named_step_id)
#  workflow_steps_processed_at_index        (processed_at)
#  workflow_steps_status_index              (status)
#  workflow_steps_task_id_index             (task_id)
#
# Foreign Keys
#
#  workflow_steps_depends_on_step_id_foreign  (depends_on_step_id => workflow_steps.workflow_step_id)
#  workflow_steps_named_step_id_foreign       (named_step_id => named_steps.named_step_id)
#  workflow_steps_task_id_foreign             (task_id => tasks.task_id)
#
module Tasker
  class WorkflowStep < ApplicationRecord
    self.primary_key = :workflow_step_id
    belongs_to :task
    belongs_to :named_step
    belongs_to :depends_on_step, class_name: 'WorkflowStep', optional: true

    validates :status, presence: true, inclusion: { in: Constants::VALID_WORKFLOW_STEP_STATUSES }

    delegate :name, to: :named_step

    def self.get_steps_for_task(task, templates)
      named_steps = NamedStep.create_named_steps_from_templates(templates)
      steps =
        templates.map do |template|
          named_step = named_steps.find { |ns| template.name == ns.name }
          NamedTasksNamedStep.associate_named_step_with_named_task(task, template, named_step)
          step = where(task_id: task.task_id, named_step_id: named_step.named_step_id).first
          step ||= build_default_step!(task, template, named_step)
          step
        end
      set_up_dependent_steps(steps, templates)
    end

    def self.set_up_dependent_steps(steps, templates)
      templates.each do |template|
        next unless template.depends_on_step

        dependent_step = steps.find { |step| step.name == template.name }
        depends_on_step = steps.find { |step| step.name == template.depends_on_step }
        dependent_step.depends_on_step_id = depends_on_step.workflow_step_id
        dependent_step.save!
      end
      steps
    end

    def self.build_default_step!(task, template, named_step)
      create!(
        {
          task_id: task.task_id,
          named_step_id: named_step.named_step_id,
          status: Constants::WorkflowStepStatuses::PENDING,
          retryable: template.default_retryable,
          retry_limit: template.default_retry_limit,
          skippable: template.skippable,
          in_process: false,
          inputs: task.context,
          processed: false,
          attempts: 0,
          results: {}
        }
      )
    end

    def self.get_viable_steps(task, sequence)
      unfinished_steps = sequence.steps.filter { |step| !step.processed && !step.in_process }
      unfinished_step_ids = unfinished_steps.map(&:workflow_step_id)
      viable_steps = []
      unfinished_steps.each do |step|
        next if step.in_process
        next if step.processed
        next if step.status == Constants::WorkflowStepStatuses::CANCELLED
        next if step.status == Constants::WorkflowStepStatuses::IN_PROGRESS
        next if step.attempts.positive? && !step.retryable
        next if step.attempts >= step.retry_limit
        next if step.depends_on_step_id && unfinished_step_ids.include?(step.depends_on_step_id)

        if step.backoff_request_seconds && step.last_attempted_at
          backoff_end = step.last_attempted_at + step.backoff_request_seconds
          next if Time.zone.now < backoff_end
        end
        next if task&.bypass_steps&.include?(step.name) && step.skippable

        viable_steps << step
      end
      viable_steps
    end

    def self.get_dependent_step_from_sequence(
      step,
      sequence,
      require_results = true,
      require_inputs = false
    )
      dependent_step = sequence.steps.find { |sibling_step| step.depends_on_step_id == sibling_step.workflow_step_id }

      unless dependent_step
        raise(Tasker::ProceduralError,
              "required dependent step for #{step.workflow_step_id} not found")
      end

      unless dependent_step.processed
        raise(Tasker::ProceduralError,
              "required dependent step #{dependent_step.workflow_step_id} incomplete")
      end

      if require_results && !dependent_step.results
        raise(Tasker::ProceduralError,
              "dependent step #{dependent_step.workflow_step_id} does not have viable results")
      end

      if require_inputs && !dependent_step.inputs
        raise(Tasker::ProceduralError,
              "dependent step #{dependent_step.workflow_step_id} does not have viable inputs")
      end

      dependent_step
    end

    def complete?
      status == Constants::WorkflowStepStatuses::COMPLETE
    end

    def in_progress?
      status == Constants::WorkflowStepStatuses::IN_PROGRESS
    end

    def pending?
      status == Constants::WorkflowStepStatuses::PENDING
    end

    def in_error?
      status == Constants::WorkflowStepStatuses::ERROR
    end

    def cancelled?
      status == Constants::WorkflowStepStatuses::CANCELLED
    end
  end
end
