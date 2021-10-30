# typed: strict
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
  class WorkflowStepSerializer < ActiveModel::Serializer
    attributes :task_id, :workflow_step_id, :name, :depends_on_step_id, :status, :attempts, :skippable, :retryable, :retry_limit, :processed, :processed_at, :in_process, :backoff_request_seconds, :last_attempted_at, :inputs, :results
  end
end
