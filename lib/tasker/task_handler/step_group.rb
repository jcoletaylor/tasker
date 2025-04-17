# typed: false
# frozen_string_literal: true

module Tasker
  module TaskHandler
    class StepGroup
      attr_accessor :prior_incomplete_steps,
                    :this_pass_complete_steps,
                    :still_incomplete_steps,
                    :still_working_steps,
                    :this_pass_complete_step_ids

      def self.build(task, sequence, steps)
        inst = new(task, sequence, steps)
        inst.build
        inst
      end

      def initialize(task, sequence, steps)
        @task = task
        @sequence = sequence
        @steps = steps
      end

      def build
        build_prior_incomplete_steps
        build_this_pass_complete_steps
        build_still_incomplete_steps
        build_still_working_steps
      end

      def build_prior_incomplete_steps
        # determine which states were incomplete by traversing the entire DAG
        self.prior_incomplete_steps = []

        # Find all root steps (those without parents)
        root_steps = @sequence.steps.select { |step| step.parents.empty? }

        # Recursively traverse the DAG to find all incomplete steps
        find_incomplete_steps(root_steps, [])
      end

      # Helper method to recursively traverse the DAG and find incomplete steps
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

      def build_this_pass_complete_steps
        # The steps passed into finalize are those processed in this pass
        # Check which ones completed in a valid state
        self.this_pass_complete_steps = []
        @steps.each do |step|
          this_pass_complete_steps << step if Tasker::Constants::VALID_STEP_COMPLETION_STATES.include?(step.status)
        end
        self.this_pass_complete_step_ids = this_pass_complete_steps.map(&:workflow_step_id)
      end

      def build_still_incomplete_steps
        # What was incomplete from the prior DAG traversal that is still incomplete now
        self.still_incomplete_steps = []
        prior_incomplete_steps.each do |step|
          still_incomplete_steps << step if this_pass_complete_step_ids.exclude?(step.workflow_step_id)
        end
      end

      def build_still_working_steps
        # What is still working from the incomplete steps but in a valid, retryable state
        self.still_working_steps = []
        still_incomplete_steps.each do |step|
          still_working_steps << step if Tasker::Constants::VALID_STEP_STILL_WORKING_STATES.include?(step.status)
        end
      end

      # if nothing was incomplete in prior iteration, complete is true
      # if nothing is still incomplete after this pass, complete is true
      def complete?
        prior_incomplete_steps.empty? || still_incomplete_steps.empty?
      end

      def pending?
        still_working_steps.length.positive?
      end
    end
  end
end
