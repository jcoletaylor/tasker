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
require 'rails_helper'
require_relative '../../helpers/task_helpers'
require_relative '../../mocks/dummy_task'

module Tasker
  RSpec.describe WorkflowStep do
    let(:helper)       { Helpers::TaskHelpers.new                             }
    let(:task_handler) { helper.factory.get(Helpers::TaskHelpers::DUMMY_TASK) }

    before(:all) do
      DependentSystem.find_or_create_by!(name: Helpers::TaskHelpers::DEPENDENT_SYSTEM)
    end

    context 'Task and StepTemplate Logic' do
      it 'is able to build a named step from a step template' do
        template = task_handler.step_templates[0]
        named_steps = NamedStep.create_named_steps_from_templates([template])
        expect(named_steps[0]).not_to be_nil
        expect(named_steps[0].name).to eq(template.name)
      end

      it 'is able to get associated named steps for a task' do
        task = task_handler.initialize_task!(helper.task_request({ reason: 'associated named steps test' }))
        expect(task.save).to be_truthy
        steps = described_class.get_steps_for_task(task, task_handler.step_templates)
        expect(steps.length).to eq(4)
        expect(steps.map(&:status)).to eq(%w[pending pending pending pending])
      end

      it 'is able to get viable steps for task and sequence' do
        task = task_handler.initialize_task!(helper.task_request({ name: Helpers::TaskHelpers::DUMMY_TASK_TWO }))
        expect(task.save).to be_truthy
        sequence = task_handler.get_sequence(task)
        # reset steps to default so we can manipulate them for validation
        sequence.steps.each do |step|
          helper.reset_step_to_default(step)
          expect(step.save).to be_truthy
        end
        step_one = sequence.steps.find { |step| step.name == DummyTask::STEP_ONE }
        step_two = sequence.steps.find { |step| step.name == DummyTask::STEP_TWO }
        viable_steps = described_class.get_viable_steps(task, sequence)
        expect(viable_steps).to eq([step_one, step_two])
        viable_steps.each do |step|
          helper.mark_step_complete(step)
        end
        sequence = task_handler.get_sequence(task)
        step_three = sequence.steps.find { |step| step.name == DummyTask::STEP_THREE }
        viable_steps = described_class.get_viable_steps(task, sequence)
        expect(viable_steps).to eq([step_three])
        viable_steps.each do |step|
          helper.mark_step_complete(step)
        end
        sequence = task_handler.get_sequence(task)
        step_four = sequence.steps.find { |step| step.name == DummyTask::STEP_FOUR }
        viable_steps = described_class.get_viable_steps(task, sequence)
        expect(viable_steps).to eq([step_four])
      end

      it 'does not count processed / processing / cancelled as viable' do
        task = task_handler.initialize_task!(helper.task_request({ reason: 'only viable states', name: Helpers::TaskHelpers::DUMMY_TASK_TWO }))
        expect(task.save).to be_truthy
        sequence = task_handler.get_sequence(task)
        # reset steps to default so we can manipulate them for validation
        sequence.steps.each do |step|
          helper.reset_step_to_default(step)
          expect(step.save).to be_truthy
        end
        step_one = sequence.steps.find { |step| step.name == DummyTask::STEP_ONE }
        step_two = sequence.steps.find { |step| step.name == DummyTask::STEP_TWO }
        step_one.update({ in_process: true })
        sequence = task_handler.get_sequence(task)
        viable_steps = described_class.get_viable_steps(task, sequence)
        expect(viable_steps).to eq([step_two])
        step_two.update({ status: Constants::WorkflowStepStatuses::CANCELLED })
        sequence = task_handler.get_sequence(task)
        viable_steps = described_class.get_viable_steps(task, sequence)
        expect(viable_steps).to eq([])
      end

      it 'does not count steps in backoff as viable' do
        task = task_handler.initialize_task!(helper.task_request({ reason: 'no backoff', name: Helpers::TaskHelpers::DUMMY_TASK_TWO }))
        expect(task.save).to be_truthy
        sequence = task_handler.get_sequence(task)
        # reset steps to default so we can manipulate them for validation
        sequence.steps.each do |step|
          helper.reset_step_to_default(step)
          expect(step.save).to be_truthy
        end
        step_one = sequence.steps.find { |step| step.name == DummyTask::STEP_ONE }
        step_two = sequence.steps.find { |step| step.name == DummyTask::STEP_TWO }
        step_one.update({ backoff_request_seconds: 30, last_attempted_at: Time.zone.now })
        sequence = task_handler.get_sequence(task)
        viable_steps = described_class.get_viable_steps(task, sequence)
        expect(viable_steps).to eq([step_two])
      end

      it 'sets task to pending if steps valid but not accomplishable yet' do
        task = task_handler.initialize_task!(helper.task_request({ reason: 'task set to pending', name: Helpers::TaskHelpers::DUMMY_TASK_TWO }))
        expect(task.save).to be_truthy
        sequence = task_handler.get_sequence(task)
        # reset steps to default so we can manipulate them for validation
        sequence.steps.each do |step|
          helper.reset_step_to_default(step)
          expect(step.save).to be_truthy
        end
        step_one = sequence.steps.find { |step| step.name == DummyTask::STEP_ONE }
        step_two = sequence.steps.find { |step| step.name == DummyTask::STEP_TWO }
        step_three = sequence.steps.find { |step| step.name == DummyTask::STEP_THREE }
        step_three.update({ status: Constants::WorkflowStepStatuses::IN_PROGRESS })
        task.reload
        step_three = task.workflow_steps.includes(:named_step).where(named_step: { name: DummyTask::STEP_THREE }).first
        expect(step_three.status).to eq(Constants::WorkflowStepStatuses::IN_PROGRESS)
        sequence = task_handler.get_sequence(task)
        viable_steps = described_class.get_viable_steps(task, sequence)
        expect(viable_steps).to eq([step_one, step_two])
        task_handler.handle(task)
        task.reload
        sequence = task_handler.get_sequence(task)
        step_three = sequence.steps.find { |step| step.name == DummyTask::STEP_THREE }
        step_four = sequence.steps.find { |step| step.name == DummyTask::STEP_FOUR }
        viable_steps = described_class.get_viable_steps(task, sequence)
        expect(viable_steps).to eq([])
        expect([step_three.status, step_four.status]).to eq(%w[in_progress pending])
        expect(task.status).to eq(Constants::TaskStatuses::PENDING)
      end

      it 'is able to set the action in error if a step is in error' do
        task = task_handler.initialize_task!(helper.task_request({ reason: 'task set to error', name: Helpers::TaskHelpers::DUMMY_TASK_TWO }))
        expect(task.save).to be_truthy
        sequence = task_handler.get_sequence(task)
        # reset steps to default so we can manipulate them for validation
        sequence.steps.each do |step|
          helper.reset_step_to_default(step)
          expect(step.save).to be_truthy
        end
        step_one = sequence.steps.find { |step| step.name == DummyTask::STEP_ONE }
        step_two = sequence.steps.find { |step| step.name == DummyTask::STEP_TWO }
        step_one.update({ status: Constants::WorkflowStepStatuses::ERROR, attempts: step_one.retry_limit + 1 })
        sequence = task_handler.get_sequence(task)
        viable_steps = described_class.get_viable_steps(task, sequence)
        expect(viable_steps).to eq([step_two])
        task_handler.handle(task)
        task.reload
        expect(task.status).to eq(Constants::TaskStatuses::ERROR)
      end
    end
  end
end
