# typed: false
# frozen_string_literal: true

require_relative '../../../lib/tasker/state_machine/step_state_machine'

module Tasker
  class WorkflowStep < ApplicationRecord
    PROVIDES_EDGE_NAME = 'provides'

    self.primary_key = :workflow_step_id
    belongs_to :task
    belongs_to :named_step
    # belongs_to :depends_on_step, class_name: 'WorkflowStep', optional: true
    has_many  :incoming_edges,
              class_name: 'WorkflowStepEdge',
              foreign_key: :to_step_id,
              dependent: :destroy,
              inverse_of: :to_step
    has_many  :outgoing_edges,
              class_name: 'WorkflowStepEdge',
              foreign_key:
              :from_step_id,
              dependent: :destroy,
              inverse_of: :from_step
    has_many :parents, through: :incoming_edges, source: :from_step
    has_many :children, through: :outgoing_edges, source: :to_step
    has_many :siblings, through: :outgoing_edges, source: :from_step
    has_many :workflow_step_transitions, inverse_of: :workflow_step, dependent: :destroy

    validates :named_step_id, uniqueness: { scope: :task_id, message: 'must be unique within the same task' }
    validate :name_uniqueness_within_task

    delegate :name, to: :named_step

    # State machine integration
    def state_machine
      @state_machine ||= Tasker::StateMachine::StepStateMachine.new(
        self,
        transition_class: Tasker::WorkflowStepTransition,
        association_name: :workflow_step_transitions
      )
    end

    # Status is now entirely managed by the state machine
    def status
      if new_record?
        # For new records, return the initial state
        Tasker::Constants::WorkflowStepStatuses::PENDING
      else
        # For persisted records, use state machine
        state_machine.current_state
      end
    end

    # Finds a WorkflowStep with the given name by traversing the DAG
    # @param steps [Array<WorkflowStep>] Array of WorkflowStep instances to search through
    # @param name [String] Name of the step to find
    # @return [WorkflowStep, nil] The first matching step found or nil if none exists
    def self.find_step_by_name(steps, name)
      return nil if steps.empty? || name.nil?

      # First check if any of the provided steps match the name
      matching_step = steps.find { |step| step.name == name }
      return matching_step if matching_step

      # If not found in the provided steps, recursively search through children
      steps.each do |step|
        # Get all children of the current step
        children = step.children.to_a

        # Recursively search through children
        result = find_step_by_name(children, name)
        return result if result
      end

      # No matching step found
      nil
    end

    def self.get_steps_for_task(task, templates)
      named_steps = NamedStep.create_named_steps_from_templates(templates)
      steps =
        templates.map do |template|
          named_step = named_steps.find { |ns| template.name == ns.name }
          NamedTasksNamedStep.associate_named_step_with_named_task(task, template, named_step)
          step = where(task_id: task.task_id, named_step_id: named_step.named_step_id).first
          step ||= build_default_step!(task, template, named_step)
          step
        end
      set_up_dependent_steps(steps, templates)
    end

    def self.set_up_dependent_steps(steps, templates)
      templates.each do |template|
        next if template.all_dependencies.empty?

        dependent_step = steps.find { |step| step.name == template.name }
        template.all_dependencies.each do |dependency|
          provider_step = steps.find { |step| step.name == dependency }
          unless provider_step.outgoing_edges.exists?(to_step: dependent_step)
            provider_step.add_provides_edge!(dependent_step)
          end
        end
      end
      steps
    end

    def self.build_default_step!(task, template, named_step)
      # Create the step first without status
      step_attributes = {
        task_id: task.task_id,
        named_step_id: named_step.named_step_id,
        retryable: template.default_retryable,
        retry_limit: template.default_retry_limit,
        skippable: template.skippable,
        in_process: false,
        inputs: task.context,
        processed: false,
        attempts: 0,
        results: {}
      }

      step = new(step_attributes)

      step.save!
      step
    end

    def self.get_viable_steps(task, sequence)
      # Ensure we have the latest data from the database
      task.reload if task.persisted?

      # Get all steps with fresh data from the database
      fresh_steps = {}
      sequence.steps.each do |step|
        fresh_step = step.persisted? ? Tasker::WorkflowStep.find(step.workflow_step_id) : step
        fresh_steps[fresh_step.workflow_step_id] = fresh_step
      end

      # Get all steps that aren't processed or in_process
      unfinished_steps = fresh_steps.values.reject { |step| step.processed || step.in_process }

      # First, build a dependency map and identify root steps (those with no parents)
      dependency_map = {}
      root_steps = []

      unfinished_steps.each do |step|
        # Get fresh parent information
        parent_ids = step.parents.map(&:workflow_step_id)
        dependency_map[step.workflow_step_id] = parent_ids

        # If no parents, this is a root step
        root_steps << step if parent_ids.empty?
      end

      # Handle special case for in_progress steps
      if unfinished_steps.any?(&:in_progress?)
        # If any step is in_progress, only include viable root steps
        viable_steps = root_steps.select { |step| is_step_viable?(step, task) }
        return viable_steps
      end

      # Find all viable steps using the dependency map
      viable_steps = []

      # First add any root steps that are viable
      root_steps.each do |step|
        viable_steps << step if is_step_viable?(step, task)
      end

      # Then find all steps with completed parents
      unfinished_steps.each do |step|
        # Skip root steps (already processed) and steps already in viable_steps
        next if dependency_map[step.workflow_step_id].empty? || viable_steps.include?(step)

        # Check if all parents are complete
        all_parents_complete = dependency_map[step.workflow_step_id].all? do |parent_id|
          parent_step = fresh_steps[parent_id]
          parent_step.complete?
        end

        # If all parents are complete and the step is viable, add it
        viable_steps << step if all_parents_complete && is_step_viable?(step, task)
      end

      viable_steps
    end

    def self.is_step_viable?(step, task)
      # First check if step is ready
      return false unless step.ready?

      # Check if all parents are complete
      return false unless all_parents_complete?([step])

      # Check backoff timing
      return false if in_backoff?(step)

      # Check if step is bypassed and skippable
      return false if task&.bypass_steps&.include?(step.name) && step.skippable

      # Step is viable
      true
    end

    def self.all_parents_complete?(steps)
      steps.all? do |step|
        # If no parents, always return true (no dependencies to satisfy)
        if step.parents.empty?
          true # Return true for this step's evaluation in the 'all?' block
        else
          # Check if all parents are complete
          step.parents.all? do |parent|
            # Ensure we get the latest status from the database
            fresh_parent = Tasker::WorkflowStep.find(parent.workflow_step_id)
            fresh_parent.complete?
          end
        end
      end
    end

    def self.in_backoff?(step)
      if step.backoff_request_seconds && step.last_attempted_at
        backoff_end = step.last_attempted_at + step.backoff_request_seconds
        return true if Time.zone.now < backoff_end
      end

      false
    end

    def add_provides_edge!(to_step)
      outgoing_edges.create!(to_step: to_step, name: PROVIDES_EDGE_NAME)
    end

    def complete?
      status == Constants::WorkflowStepStatuses::COMPLETE
    end

    def in_progress?
      status == Constants::WorkflowStepStatuses::IN_PROGRESS
    end

    def pending?
      status == Constants::WorkflowStepStatuses::PENDING
    end

    def in_error?
      status == Constants::WorkflowStepStatuses::ERROR
    end

    def cancelled?
      status == Constants::WorkflowStepStatuses::CANCELLED
    end

    def ready_status?
      Constants::UNREADY_WORKFLOW_STEP_STATUSES.exclude?(status)
    end

    def ready?
      ready = true
      ready = false if in_process
      ready = false if processed
      ready = false unless ready_status?
      ready = false if attempts.positive? && !retryable
      ready = false if attempts >= retry_limit
      ready
    end

    private

    # Custom validation to ensure step names are unique within a task
    def name_uniqueness_within_task
      return unless named_step && task

      # Find all steps within the same task that have the same name
      matching_steps = self.class.where(task_id: task_id)
                           .joins(:named_step)
                           .where(named_step: { name: name })
                           .where.not(workflow_step_id: workflow_step_id) # Exclude self when updating

      errors.add(:base, "Step name '#{name}' must be unique within the same task") if matching_steps.exists?
    end
  end
end
