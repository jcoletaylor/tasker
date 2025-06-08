# typed: false
# frozen_string_literal: true

require 'digest'
require_relative '../../../lib/tasker/state_machine/task_state_machine'

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
#  tasks_tags_idx                (tags) USING gin
#  tasks_tags_idx1               (tags) USING gin
#
# Foreign Keys
#
#  tasks_named_task_id_foreign  (named_task_id => named_tasks.named_task_id)
#
module Tasker
  # Task represents a workflow process that contains multiple workflow steps.
  # Each Task is identified by a name and has a context which defines the parameters for the task.
  # Tasks track their status via state machine transitions, initiator, source system, and other metadata.
  #
  # @example Creating a task from a task request
  #   task_request = Tasker::Types::TaskRequest.new(name: 'process_order', context: { order_id: 123 })
  #   task = Tasker::Task.create_with_defaults!(task_request)
  #
  class Task < ApplicationRecord
    # Regular expression to sanitize strings for database operations
    ALPHANUM_PLUS_HYPHEN_DASH = /[^0-9a-z\-_]/i

    self.primary_key = :task_id
    after_initialize :init_defaults, if: :new_record?
    belongs_to :named_task
    has_many :workflow_steps, dependent: :destroy
    has_many :task_annotations, dependent: :destroy
    has_many :annotation_types, through: :task_annotations
    has_many :task_transitions, inverse_of: :task, dependent: :destroy

    validates :context, presence: true
    validates :requested_at, presence: true
    validate :unique_identity_hash, on: :create

    delegate :name, to: :named_task
    delegate :to_mermaid, to: :diagram

    has_one :task_execution_context, class_name: 'Tasker::TaskExecutionContext', primary_key: :task_id
    has_one :task_workflow_summary, class_name: 'Tasker::TaskWorkflowSummary', primary_key: :task_id

    # State machine integration
    def state_machine
      @state_machine ||= Tasker::StateMachine::TaskStateMachine.new(
        self,
        transition_class: Tasker::TaskTransition,
        association_name: :task_transitions
      )
    end

    # Status is now entirely managed by the state machine
    def status
      if new_record?
        # For new records, return the initial state
        Tasker::Constants::TaskStatuses::PENDING
      else
        # For persisted records, use state machine
        state_machine.current_state
      end
    end

    # Scopes a query to find tasks with a specific annotation value
    #
    # @param name [String] The annotation type name
    # @param key [String, Symbol] The key within the annotation to match
    # @param value [String] The value to match against
    # @return [ActiveRecord::Relation] Tasks matching the annotation criteria
    scope :by_annotation,
          lambda { |name, key, value|
            clean_key = key.to_s.gsub(ALPHANUM_PLUS_HYPHEN_DASH, '')
            joins(:task_annotations, :annotation_types)
              .where({ annotation_types: { name: name.to_s.strip } })
              .where("tasker_task_annotations.annotation->>'#{clean_key}' = :value", value: value)
          }

    # Scopes a query to find tasks by their current state using state machine transitions
    #
    # @param state [String, nil] The state to filter by. If nil, returns all tasks with current state information
    # @return [ActiveRecord::Relation] Tasks with current state, optionally filtered by specific state
    scope :by_current_state,
          lambda { |state = nil|
            relation = joins(<<-SQL.squish)
              INNER JOIN (
                SELECT DISTINCT ON (task_id) task_id, to_state
                FROM tasker_task_transitions
                ORDER BY task_id, sort_key DESC
              ) current_transitions ON current_transitions.task_id = tasker_tasks.task_id
            SQL

            if state.present?
              relation.where(current_transitions: { to_state: state })
            else
              relation
            end
          }

    # Includes all associated models for efficient querying
    #
    # @return [ActiveRecord::Relation] Tasks with all associated records preloaded
    scope :with_all_associated, lambda {
      includes(:named_task)
        .includes(workflow_steps: %i[named_step parents children])
        .includes(task_annotations: %i[annotation_type])
    }

    # Creates a task with default values from a task request and saves it to the database
    #
    # @param task_request [Tasker::Types::TaskRequest] The task request containing task parameters
    # @return [Tasker::Task] The created and saved task
    # @raise [ActiveRecord::RecordInvalid] If the task is invalid
    def self.create_with_defaults!(task_request)
      task = from_task_request(task_request)
      task.save!
      task
    end

    # Creates a new unsaved task instance from a task request
    #
    # @param task_request [Tasker::Types::TaskRequest] The task request containing task parameters
    # @return [Tasker::Task] A new unsaved task instance
    def self.from_task_request(task_request)
      named_task = Tasker::NamedTask.find_or_create_by!(name: task_request.name)
      # Extract values from task_request, removing nils
      request_values = get_request_options(task_request)
      # Merge defaults with request values
      options = get_default_task_request_options(named_task).merge(request_values)

      task = new(options)
      task.named_task = named_task
      task
    end

    # Extracts and compacts options from a task request
    #
    # @param task_request [Tasker::Types::TaskRequest] The task request to extract options from
    # @return [Hash] Hash of non-nil task options from the request
    def self.get_request_options(task_request)
      {
        initiator: task_request.initiator,
        source_system: task_request.source_system,
        reason: task_request.reason,
        tags: task_request.tags,
        bypass_steps: task_request.bypass_steps,
        requested_at: task_request.requested_at,
        context: task_request.context
      }.compact
    end

    # Provides default options for a task
    #
    # @param named_task [Tasker::NamedTask] The named task to associate with the task
    # @return [Hash] Hash of default task options
    def self.get_default_task_request_options(named_task)
      {
        initiator: Tasker::Constants::UNKNOWN,
        source_system: Constants::UNKNOWN,
        reason: Tasker::Constants::UNKNOWN,
        complete: false,
        tags: [],
        bypass_steps: [],
        requested_at: Time.zone.now,
        named_task_id: named_task.named_task_id
      }
    end

    # Finds a workflow step by its name
    #
    # @param name [String] The name of the step to find
    # @return [Tasker::WorkflowStep, nil] The workflow step with the given name, or nil if not found
    def get_step_by_name(name)
      workflow_steps.includes(:named_step).where(named_step: { name: name }).first
    end

    # Gets or creates a diagram representation of this task
    #
    # @param base_url [String, nil] The base URL to use for links in the diagram, defaults to nil
    # @return [Tasker::TaskDiagram] The diagram representation of this task
    def diagram(base_url = nil)
      @diagram ||= Tasker::TaskDiagram.new(self, base_url)
    end

    private

    # Validates that the task has a unique identity hash
    # Sets the identity hash and checks if a task with the same hash exists
    #
    # @return [void]
    def unique_identity_hash
      return errors.add(:named_task_id, 'no task name found') unless named_task

      set_identity_hash
      inst = self.class.where(identity_hash: identity_hash).where.not(task_id: task_id).first
      errors.add(:identity_hash, 'is identical to a request made in the last minute') if inst
    end

    # Returns a hash of values that uniquely identify this task
    #
    # @return [Hash] Hash of identifying values
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

    # Initializes default values for a new task
    #
    # @return [void]
    def init_defaults
      return unless new_record?

      # Apply defaults only for attributes that haven't been set
      task_defaults.each do |attribute, default_value|
        self[attribute] = default_value if self[attribute].nil?
      end
    end

    # Returns a hash of default values for a task
    #
    # @return [Hash] Hash of default values
    def task_defaults
      @task_defaults ||= {
        requested_at: Time.zone.now,
        initiator: Tasker::Constants::UNKNOWN,
        source_system: Tasker::Constants::UNKNOWN,
        reason: Tasker::Constants::UNKNOWN,
        complete: false,
        tags: [],
        bypass_steps: []
      }
    end

    # Gets the identity strategy instance from configuration
    #
    # @return [Object] The identity strategy instance
    def identity_strategy
      @identity_strategy ||= Tasker.configuration.engine.identity_strategy_instance
    end

    # Sets the identity hash for this task using the configured identity strategy
    #
    # @return [String] The generated identity hash
    def set_identity_hash
      self.identity_hash = identity_strategy.generate_identity_hash(self, identity_options)
    end
  end
end
