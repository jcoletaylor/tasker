# typed: false
# frozen_string_literal: true

require 'digest'

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
  class Task < ApplicationRecord
    extend T::Sig

    ALPHANUM_PLUS_HYPHEN_DASH = /[^0-9a-z\-\_]/i

    self.primary_key = :task_id
    after_initialize :init_defaults, if: :new_record?
    belongs_to :named_task
    has_many :workflow_steps, dependent: :destroy
    has_many :task_annotations, dependent: :destroy
    has_many :annotation_types, through: :task_annotations

    validates :context, presence: true
    validates :requested_at, presence: true
    validates :status, presence: true, inclusion: { in: Tasker::Constants::VALID_TASK_STATUSES }
    validate :unique_identity_hash, on: :create

    delegate :name, to: :named_task

    scope :by_annotation,
          lambda { |name, key, value|
            clean_key = key.to_s.gsub(ALPHANUM_PLUS_HYPHEN_DASH, '')
            joins(:task_annotations, :annotation_types)
              .where({ annotation_types: { name: name.to_s.strip } })
              .where("tasker_task_annotations.annotation->>'#{clean_key}' = :value", value: value)
          }

    scope :with_all_associated, lambda {
      includes(:named_task).includes(workflow_steps: %i[named_step parents children]).includes(task_annotations: %i[annotation_type])
    }

    # typed: true
    sig { params(task_request: Tasker::Types::TaskRequest).returns(Task) }
    def self.create_with_defaults!(task_request)
      task = from_task_request(task_request)
      task.save!
      task
    end

    # typed: true
    sig { params(task_request: Tasker::Types::TaskRequest).returns(Task) }
    def self.from_task_request(task_request)
      named_task = Tasker::NamedTask.find_or_create_by!(name: task_request.name)
      options = {
        status: task_request.status || Tasker::Constants::TaskStatuses::PENDING,
        initiator: task_request.initiator || Tasker::Constants::UNKNOWN,
        source_system: task_request.source_system || Constants::UNKNOWN,
        reason: task_request.reason || Tasker::Constants::UNKNOWN,
        complete: false,
        tags: task_request.tags || [],
        bypass_steps: task_request.bypass_steps || [],
        requested_at: task_request.requested_at || Time.zone.now,
        context: task_request.context,
        named_task_id: named_task.named_task_id
      }
      task = new(options)
      task.named_task = named_task
      task
    end

    def get_step_by_name(name)
      workflow_steps.includes(:named_step).where(named_step: { name: name }).first
    end

    private

    def unique_identity_hash
      return errors.add(:named_task_id, 'no task name found') unless named_task

      set_identity_hash
      inst = self.class.where(identity_hash: identity_hash).where.not(task_id: task_id).first
      errors.add(:identity_hash, 'is identical to a request made in the last minute') if inst
    end

    def identity_options
      # a task can be described as identical to a prior request if
      # it has the same name, initiator, source system, reason
      # bypass steps, and critically, the same identical context for the request
      # if all of these are the same, and it was requested within the same minute
      # then we can assume some client side or queue side duplication is happening
      {
        name: name,
        initiator: initiator,
        source_system: source_system,
        context: context,
        reason: reason,
        bypass_steps: bypass_steps || [],
        # not allowing structurally identical requests within the same minute
        # this is a fuzzy match of course, at the 59 / 00 mark there could be overlap
        # but this feels like a pretty good level of identity checking
        # without being exhaustive
        requested_at: requested_at.strftime('%Y-%m-%d %H:%M')
      }
    end

    def init_defaults
      return unless new_record?

      self.status ||= Tasker::Constants::TaskStatuses::PENDING
      self.requested_at ||= Time.zone.now
      self.initiator ||= Tasker::Constants::UNKNOWN
      self.source_system ||= Tasker::Constants::UNKNOWN
      self.reason ||= Tasker::Constants::UNKNOWN
      self.complete ||= false
      self.tags ||= []
      self.bypass_steps ||= []
    end

    def set_identity_hash
      self.identity_hash = Digest::SHA256.hexdigest(identity_options.to_json)
    end
  end
end
