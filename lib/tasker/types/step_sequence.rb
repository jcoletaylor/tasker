# typed: false
# frozen_string_literal: true

module Tasker
  module Types
    # StepSequence represents a sequence of workflow steps to be executed.
    #
    # It provides a container for an array of WorkflowStep instances and
    # utility methods for working with the step sequence.
    class StepSequence < Dry::Struct
      # @!attribute [r] steps
      #   @return [Array<Tasker::WorkflowStep>] List of workflow steps in this sequence
      attribute :steps, Types::Array.default([].freeze)

      # Finds a step in the sequence by its name
      #
      # @param name [String] The name of the step to find
      # @return [Tasker::WorkflowStep, nil] The matching step or nil if not found
      def find_step_by_name(name)
        Tasker::WorkflowStep.find_step_by_name(steps, name)
      end
    end
  end
end
