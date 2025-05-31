# typed: false
# frozen_string_literal: true

require 'rails_helper'
require_relative '../../mocks/dummy_task'

module Tasker
  RSpec.describe(WorkflowStep) do
    before(:all) do
      DependentSystem.find_or_create_by!(name: 'dummy-system')

      # Register both dummy task handlers
      register_task_handler('dummy_task', DummyTask)
      register_task_handler('dummy_task_two', DummyTask)
    end

    context 'Task and StepTemplate Logic' do
      it 'is able to build a named step from a step template' do
        create(:dependent_system, name: 'test-system')
        template = Tasker::Types::StepTemplate.new(
          name: 'test_step',
          dependent_system: 'test-system',
          description: 'Test step template',
          default_retryable: true,
          default_retry_limit: 3,
          skippable: false,
          handler_class: DummyTask::Handler
        )

        named_steps = NamedStep.create_named_steps_from_templates([template])
        expect(named_steps.first).not_to(be_nil)
        expect(named_steps.first.name).to(eq(template.name))
      end

      it 'is able to get associated named steps for a task' do
        task = create_dummy_task_workflow(reason: 'associated named steps test')

        task_handler = Tasker::HandlerFactory.instance.get('dummy_task')

        steps = described_class.get_steps_for_task(task, task_handler.step_templates)
        expect(steps.length).to(eq(4))
        expect(steps.map(&:status)).to(eq(%w[pending pending pending pending]))
      end

      it 'is able to get viable steps for task and sequence' do
        task = create_dummy_task_two_workflow

        sequence = get_sequence_for_task(task)

        sequence.steps.each { |step| reset_step_to_pending(step) }

        step_one = find_step_by_name(task, 'step-one')
        step_two = find_step_by_name(task, 'step-two')

        viable_steps = described_class.get_viable_steps(task, sequence)
        expect(viable_steps).to(eq([step_one, step_two]))

        viable_steps.each { |step| complete_step_via_state_machine(step) }

        sequence = get_sequence_for_task(task)
        step_three = find_step_by_name(task, 'step-three')
        viable_steps = described_class.get_viable_steps(task, sequence)
        expect(viable_steps).to(eq([step_three]))

        viable_steps.each { |step| complete_step_via_state_machine(step) }
        sequence = get_sequence_for_task(task)
        step_four = find_step_by_name(task, 'step-four')
        viable_steps = described_class.get_viable_steps(task, sequence)
        expect(viable_steps).to(eq([step_four]))
      end

      it 'does not count processed / processing / cancelled as viable' do
        task = create_dummy_task_two_workflow(reason: 'only viable states')

        sequence = get_sequence_for_task(task)
        sequence.steps.each { |step| reset_step_to_pending(step) }

        step_one = find_step_by_name(task, 'step-one')
        step_two = find_step_by_name(task, 'step-two')

        set_step_in_progress(step_one)

        sequence = get_sequence_for_task(task)
        viable_steps = described_class.get_viable_steps(task, sequence)
        expect(viable_steps).to(eq([step_two]))

        set_step_cancelled(step_two)

        sequence = get_sequence_for_task(task)
        viable_steps = described_class.get_viable_steps(task, sequence)
        expect(viable_steps).to(eq([]))
      end

      it 'does not count steps in backoff as viable' do
        task = create_dummy_task_two_workflow(reason: 'no backoff')

        sequence = get_sequence_for_task(task)
        sequence.steps.each { |step| reset_step_to_pending(step) }

        step_one = find_step_by_name(task, 'step-one')
        step_two = find_step_by_name(task, 'step-two')

        set_step_in_backoff(step_one, 30)

        sequence = get_sequence_for_task(task)
        viable_steps = described_class.get_viable_steps(task, sequence)
        expect(viable_steps).to(eq([step_two]))
      end

      it 'sets task to pending if steps valid but not accomplishable yet' do
        task = create_dummy_task_two_workflow(reason: 'task set to pending')

        sequence = get_sequence_for_task(task)
        sequence.steps.each { |step| reset_step_to_pending(step) }

        step_one = find_step_by_name(task, 'step-one')
        step_two = find_step_by_name(task, 'step-two')
        step_three = find_step_by_name(task, 'step-three')

        force_step_in_progress(step_three)

        task.reload
        step_three = find_step_by_name(task, 'step-three')
        expect(step_three.status).to(eq(Constants::WorkflowStepStatuses::IN_PROGRESS))

        sequence = get_sequence_for_task(task)
        viable_steps = described_class.get_viable_steps(task, sequence)
        expect(viable_steps).to(eq([step_one, step_two]))

        task_handler = Tasker::HandlerFactory.instance.get('dummy_task')
        task_handler.handle(task)

        task.reload
        sequence = get_sequence_for_task(task)
        step_three = find_step_by_name(task, 'step-three')
        step_four = find_step_by_name(task, 'step-four')
        viable_steps = described_class.get_viable_steps(task, sequence)
        expect(viable_steps).to(eq([]))
        expect([step_three.status, step_four.status]).to(eq(%w[in_progress pending]))
        expect(task.status).to(eq(Constants::TaskStatuses::PENDING))
      end

      it 'is able to set the action in error if a step is in error' do
        task = create_dummy_task_two_workflow(reason: 'task set to error')

        sequence = get_sequence_for_task(task)
        sequence.steps.each { |step| reset_step_to_pending(step) }

        step_one = find_step_by_name(task, 'step-one')
        step_two = find_step_by_name(task, 'step-two')

        set_step_to_max_retries_error(step_one)

        sequence = get_sequence_for_task(task)
        viable_steps = described_class.get_viable_steps(task, sequence)
        expect(viable_steps).to(eq([step_two]))

        task_handler = Tasker::HandlerFactory.instance.get('dummy_task')
        task_handler.handle(task)

        task.reload
        expect(task.status).to(eq(Constants::TaskStatuses::ERROR))
      end
    end
  end
end
