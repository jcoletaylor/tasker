# typed: false
# frozen_string_literal: true

# == Schema Information
#
# Table name: named_tasks_named_steps
#
#  id                  :integer          not null, primary key
#  default_retry_limit :integer          default(3), not null
#  default_retryable   :boolean          default(TRUE), not null
#  skippable           :boolean          default(FALSE), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  named_step_id       :integer          not null
#  named_task_id       :integer          not null
#
# Indexes
#
#  named_tasks_named_steps_named_step_id_index  (named_step_id)
#  named_tasks_named_steps_named_task_id_index  (named_task_id)
#  named_tasks_steps_ids_unique                 (named_task_id,named_step_id) UNIQUE
#
# Foreign Keys
#
#  named_tasks_named_steps_named_step_id_foreign  (named_step_id => named_steps.named_step_id)
#  named_tasks_named_steps_named_task_id_foreign  (named_task_id => named_tasks.named_task_id)
#
require 'rails_helper'
require_relative '../../mocks/dummy_task'

module Tasker
  RSpec.describe NamedTasksNamedStep do
    context 'class methods' do
      let(:task_request) { TaskRequest.new(name: 'dummy_action', context: { some: :value, it_is: :great }) }
      let(:task)         { Task.create_with_defaults!(task_request)                                        }
      let(:template) do
        StepTemplate.new(
          dependent_system: 'dummy-system',
          name: 'step-one',
          description: 'Independent Step One',
          default_retryable: true,
          default_retry_limit: 3,
          skippable: false,
          handler_class: DummyTask::Handler
        )
      end
      let(:named_steps) { NamedStep.create_named_steps_from_templates([template]) }

      it 'is able to associate named tasks and named steps' do
        named_step = named_steps.first
        ntns = described_class.associate_named_step_with_named_task(task, template, named_step)
        expect(ntns.named_step).to eq(named_step)
        expect(ntns.named_task).to eq(task.named_task)
        expect(ntns.default_retry_limit).to eq(template.default_retry_limit)
        expect(ntns.default_retryable).to eq(template.default_retryable)
        expect(ntns.skippable).to eq(template.skippable)
      end
    end
  end
end
