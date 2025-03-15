# typed: strict
# frozen_string_literal: true

# == Schema Information
#
# Table name: tasks
#
#  bypass_steps  :json
#  complete      :boolean          default(FALSE), not null
#  context       :jsonb
#  identity_hash :string(128)      not null
#  initiator     :string(128)
#  reason        :string(128)
#  requested_at  :datetime         not null
#  source_system :string(128)
#  status        :string(64)       not null
#  tags          :jsonb
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  named_task_id :integer          not null
#  task_id       :bigint           not null, primary key
#
# Indexes
#
#  index_tasks_on_identity_hash  (identity_hash) UNIQUE
#  tasks_context_idx             (context) USING gin
#  tasks_context_idx1            (context) USING gin
#  tasks_identity_hash_index     (identity_hash)
#  tasks_named_task_id_index     (named_task_id)
#  tasks_requested_at_index      (requested_at)
#  tasks_source_system_index     (source_system)
#  tasks_status_index            (status)
#  tasks_tags_idx                (tags) USING gin
#  tasks_tags_idx1               (tags) USING gin
#
# Foreign Keys
#
#  tasks_named_task_id_foreign  (named_task_id => named_tasks.named_task_id)
#

module Tasker
  class TaskSerializer < ActiveModel::Serializer
    attributes :task_id, :name, :initiator, :source_system, :context, :reason, :bypass_steps, :tags, :requested_at,
               :complete, :status
    has_many :workflow_steps
    has_many :task_annotations
  end
end
