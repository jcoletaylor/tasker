# typed: false
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
require 'rails_helper'

module Tasker
  RSpec.describe(Task) do
    describe 'task creation' do
      let(:task_request) { Tasker::Types::TaskRequest.new(name: 'dummy_action', context: { dummy: true }) }
      let(:task)         { described_class.create_with_defaults!(task_request)             }

      it 'is able to create with defaults' do
        expect(task.save).to(be_truthy)
        expect(task.task_id).not_to(be_nil)
        expect(task.identity_hash).not_to(be_nil)
        # should not be able to do the same thing again instantly
        expect do
          described_class.create_with_defaults!(task_request)
        end.to(raise_error(ActiveRecord::RecordInvalid))

        next_task_request = Tasker::Types::TaskRequest.new(name: 'dummy_action', context: { dummy: true },
                                                           requested_at: 2.minutes.from_now)
        # but should be able to do it if it is requested far enough apart
        expect do
          described_class.create_with_defaults!(next_task_request)
        end.not_to(raise_error)
      end
    end
  end
end
