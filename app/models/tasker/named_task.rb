# typed: strict
# frozen_string_literal: true

# == Schema Information
#
# Table name: named_tasks
#
#  description   :string(255)
#  name          :string(64)       not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  named_task_id :integer          not null, primary key
#
# Indexes
#
#  named_tasks_name_index   (name)
#  named_tasks_name_unique  (name) UNIQUE
#
module Tasker
  class NamedTask < ApplicationRecord
    self.primary_key = :named_task_id
    has_many :tasks, dependent: :destroy
    validates :name, presence: true, uniqueness: true
  end
end
