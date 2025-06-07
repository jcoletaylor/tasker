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
    include FactoryWorkflowHelpers

    before do
      # Register the handler for factory usage
      register_task_handler(DummyTask::TASK_REGISTRY_NAME, DummyTask)
    end

    describe 'task creation' do
      it 'is able to create with defaults' do
        # Set identity strategy to hash for testing
        Tasker.configuration.engine.identity_strategy = :hash

        # Create first task using factory approach
        task = create_dummy_task_workflow(context: { dummy: true }, reason: 'task creation test')

        expect(task).to(be_persisted)
        expect(task.task_id).not_to(be_nil)
        expect(task.identity_hash).not_to(be_nil)

        # Should not be able to create the same task again instantly (same identity hash)
        expect do
          create_dummy_task_workflow(context: { dummy: true }, reason: 'task creation test')
        end.to(raise_error(ActiveRecord::RecordInvalid))

        # But should be able to create it with a different reason (different identity hash)
        expect do
          create_dummy_task_workflow(
            context: { dummy: true },
            reason: 'task creation test different',
            requested_at: 2.minutes.from_now
          )
        end.not_to(raise_error)
      end
    end
  end
end
