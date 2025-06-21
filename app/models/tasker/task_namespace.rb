# typed: false
# frozen_string_literal: true

# == Schema Information
#
# Table name: tasker_task_namespaces
#
#  name                :string(64)       not null
#  description         :string(255)
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  task_namespace_id   :integer          not null, primary key
#
# Indexes
#
#  task_namespaces_name_index   (name)
#  task_namespaces_name_unique  (name) UNIQUE
#
module Tasker
  class TaskNamespace < ApplicationRecord
    self.primary_key = :task_namespace_id

    has_many :named_tasks, dependent: :nullify

    validates :name, presence: true, uniqueness: true, length: { maximum: 64 }
    validates :description, length: { maximum: 255 }

    # Find or create default namespace - always works even if not seeded
    def self.default
      find_or_create_by!(name: 'default') do |namespace|
        namespace.description = 'Default task namespace'
      end
    end

    # Scope for non-default namespaces
    scope :custom, -> { where.not(name: 'default') }

    # Get namespace by name, with fallback to default
    def self.find_by_name_or_default(name)
      return default if name.blank? || name == 'default'

      find_by(name: name) || default
    end

    # Check if this is the default namespace
    def default?
      name == 'default'
    end

    # Get full namespace identifier
    def full_name
      name
    end
  end
end
