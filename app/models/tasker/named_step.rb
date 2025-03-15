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
module Tasker
  class NamedStep < ApplicationRecord
    extend T::Sig

    self.primary_key = :named_step_id
    belongs_to :dependent_system
    has_many :workflow_steps, dependent: :destroy
    validates :name, presence: true, uniqueness: { scope: :dependent_system_id }

    # typed: true
    sig { params(templates: T::Array[Tasker::StepTemplate]).returns(T::Array[Tasker::NamedStep]) }
    def self.create_named_steps_from_templates(templates)
      templates.map do |template|
        dependent_system = Tasker::DependentSystem.find_or_create_by!(name: template.dependent_system)
        named_step = NamedStep.find_or_create_by!(name: template.name,
                                                  dependent_system_id: dependent_system.dependent_system_id)
        named_step
      end
    end
  end
end
