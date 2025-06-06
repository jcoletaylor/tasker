# typed: false
# frozen_string_literal: true

module Tasker
  module TaskHandler
    # Manages and analyzes groups of workflow steps
    #
    # StepGroup is used to track the status of steps in a workflow and determine
    # whether a task is complete, can be finalized, or needs further processing.
    # It traverses the step dependency graph to find incomplete steps.
    class StepGroup
      # @return [Array<Tasker::WorkflowStep>] Steps that were incomplete before this processing pass
      attr_accessor :prior_incomplete_steps

      # @return [Array<Tasker::WorkflowStep>] Steps that were completed in this processing pass
      attr_accessor :this_pass_complete_steps

      # @return [Array<Tasker::WorkflowStep>] Steps that are still incomplete after this pass
      attr_accessor :still_incomplete_steps

      # @return [Array<Tasker::WorkflowStep>] Steps that are still in a working state (pending/in progress)
      attr_accessor :still_working_steps

      # @return [Array<Integer>] IDs of steps completed in this processing pass
      attr_accessor :this_pass_complete_step_ids

      # Build a StepGroup for the given task, sequence and steps
      #
      # @param task [Tasker::Task] The task being processed
      # @param sequence [Tasker::Types::StepSequence] The sequence of steps
      # @param steps [Array<Tasker::WorkflowStep>] The steps processed in the current pass
      # @return [StepGroup] A fully built step group
      def self.build(task, sequence, steps)
        inst = new(task, sequence, steps)
        inst.build
        inst
      end

      # Initialize a new StepGroup
      #
      # @param task [Tasker::Task] The task being processed
      # @param sequence [Tasker::Types::StepSequence] The sequence of steps
      # @param steps [Array<Tasker::WorkflowStep>] The steps processed in the current pass
      # @return [StepGroup] A new step group instance
      def initialize(task, sequence, steps)
        @task = task
        @sequence = sequence
        @steps = steps
      end

      # Build the step group by analyzing all step collections
      #
      # @return [void]
      def build
        build_prior_incomplete_steps
        build_this_pass_complete_steps
        build_still_incomplete_steps
        build_still_working_steps
      end

      # Find all steps that were incomplete prior to this processing pass
      #
      # @return [void]
      def build_prior_incomplete_steps
        # determine which states were incomplete by traversing the entire DAG
        self.prior_incomplete_steps = []

        # Find all root steps (those without parents)
        root_steps = @sequence.steps.select { |step| step.parents.empty? }

        # Recursively traverse the DAG to find all incomplete steps
        find_incomplete_steps(root_steps, [])
      end

      # Recursively traverse the DAG to find all incomplete steps
      #
      # @param steps [Array<Tasker::WorkflowStep>] Steps to check
      # @param visited_step_ids [Array<Integer>] IDs of steps already visited
      # @return [void]
      def find_incomplete_steps(steps, visited_step_ids)
        steps.each do |step|
          # Skip if we've already visited this step (avoid cycles, though they shouldn't exist in a DAG)
          next if visited_step_ids.include?(step.workflow_step_id)

          # Add this step to visited
          visited_step_ids << step.workflow_step_id

          # Add to prior_incomplete_steps if this step is incomplete
          prior_incomplete_steps << step if Tasker::Constants::VALID_STEP_COMPLETION_STATES.exclude?(step.status)

          # Recursively check all children
          find_incomplete_steps(step.children, visited_step_ids)
        end
      end

      # Find steps that were completed in this processing pass
      #
      # @return [void]
      def build_this_pass_complete_steps
        # The steps passed into finalize are those processed in this pass
        # Check which ones completed in a valid state
        self.this_pass_complete_steps = []
        @steps.each do |step|
          this_pass_complete_steps << step if Tasker::Constants::VALID_STEP_COMPLETION_STATES.include?(step.status)
        end
        self.this_pass_complete_step_ids = this_pass_complete_steps.map(&:workflow_step_id)
      end

      # Find steps that are still incomplete after this processing pass
      #
      # @return [void]
      def build_still_incomplete_steps
        # What was incomplete from the prior DAG traversal that is still incomplete now
        self.still_incomplete_steps = []
        prior_incomplete_steps.each do |step|
          still_incomplete_steps << step if this_pass_complete_step_ids.exclude?(step.workflow_step_id)
        end
      end

      # Find steps that are still in a working state (pending/in progress)
      #
      # @return [void]
      def build_still_working_steps
        # What is still working from the incomplete steps but in a valid, retryable state
        self.still_working_steps = []
        still_incomplete_steps.each do |step|
          still_working_steps << step if Tasker::Constants::VALID_STEP_STILL_WORKING_STATES.include?(step.status)
        end
      end

      # Check if the task can be considered complete
      #
      # A task is complete if there were no incomplete steps in the prior iteration
      # or if all previously incomplete steps are now complete.
      #
      # @return [Boolean] True if the task is complete
      def complete?
        prior_incomplete_steps.empty? || still_incomplete_steps.empty?
      end

      # Check if the task should be marked as pending for further processing
      #
      # A task is considered pending if there are still steps in a working state.
      #
      # @return [Boolean] True if the task should be pending
      def pending?
        still_working_steps.length.positive?
      end

      # Check if the task has any steps in error states
      #
      # A task has errors if any steps are in terminal error states that can't be retried.
      #
      # @return [Boolean] True if the task has error steps
      def error?
        # Use efficient database query with existing failed scope
        step_ids = @sequence.steps.map(&:workflow_step_id)
        return false if step_ids.empty?

        # Query for any steps in error state using the failed scope
        Tasker::WorkflowStep.failed.exists?(workflow_step_id: step_ids)
      end

      # Get debugging state information for the step group
      #
      # @return [Hash] Debug information about the step group state
      def debug_state
        {
          total_steps: @sequence.steps.size,
          prior_incomplete_count: prior_incomplete_steps.size,
          complete_this_pass_count: this_pass_complete_steps.size,
          still_incomplete_count: still_incomplete_steps.size,
          still_working_count: still_working_steps.size,
          step_statuses: @sequence.steps.map { |s| { id: s.workflow_step_id, name: s.name, status: s.status } },
          is_complete: complete?,
          is_pending: pending?,
          has_errors: error?
        }
      end
    end
  end
end
