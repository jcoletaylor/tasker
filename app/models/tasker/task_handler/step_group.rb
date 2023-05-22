# typed: false
# frozen_string_literal: true

module Tasker
  module TaskHandler
    class StepGroup
      extend T::Sig
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
        # determine which states were incomplete for the whole sequence before this round
        self.prior_incomplete_steps = []
        @sequence.steps.each do |step|
          prior_incomplete_steps << step unless Tasker::Constants::VALID_STEP_COMPLETION_STATES.include?(step.status)
        end
      end

      def build_this_pass_complete_steps
        # the steps that are passed into finalize are not the whole sequence
        # just what has been worked on in this pass, so we need to see what completed
        # in a valid state, and what has still to be done
        self.this_pass_complete_steps = []
        @steps.each do |step|
          this_pass_complete_steps << step if Tasker::Constants::VALID_STEP_COMPLETION_STATES.include?(step.status)
        end
        self.this_pass_complete_step_ids = this_pass_complete_steps.map(&:workflow_step_id)
      end

      def build_still_incomplete_steps
        # what was incomplete from the prior pass that is still incopmlete now
        self.still_incomplete_steps = []
        prior_incomplete_steps.each do |step|
          still_incomplete_steps << step unless this_pass_complete_step_ids.include?(step.workflow_step_id)
        end
      end

      def build_still_working_steps
        # what is still working but in a valid, retryable state
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
