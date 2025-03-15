# typed: false
# frozen_string_literal: true

# == Schema Information
#
# Table name: named_steps
#
#  description         :string(255)
#  name                :string(128)      not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  dependent_system_id :integer          not null
#  named_step_id       :integer          not null, primary key
#
# Indexes
#
#  named_step_by_system_uniq              (dependent_system_id,name) UNIQUE
#  named_steps_dependent_system_id_index  (dependent_system_id)
#  named_steps_name_index                 (name)
#
# Foreign Keys
#
#  named_steps_dependent_system_id_foreign  (dependent_system_id => dependent_systems.dependent_system_id)
#
require 'rails_helper'
require_relative '../../mocks/dummy_task'

module Tasker
  RSpec.describe(NamedStep) do
    context 'class methods' do
      it 'is able to create named steps from step templates' do
        templates = [
          StepTemplate.new(
            dependent_system: 'dummy-system',
            name: 'step-one',
            description: 'Independent Step One',
            default_retryable: true,
            default_retry_limit: 3,
            skippable: false,
            handler_class: DummyTask::Handler
          ),
          StepTemplate.new(
            dependent_system: 'dummy-system',
            name: 'step-two',
            description: 'Independent Step Two',
            default_retryable: true,
            default_retry_limit: 3,
            skippable: false,
            handler_class: DummyTask::Handler
          )
        ]
        named_steps = described_class.create_named_steps_from_templates(templates)
        expect(named_steps.length).to(be_positive)
        expect(named_steps.map(&:name)).to(eq(%w[step-one step-two]))
      end
    end
  end
end
