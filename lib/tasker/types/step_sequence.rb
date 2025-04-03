# typed: true
# frozen_string_literal: true

module Tasker
  module Types
    # StepSequence represents a sequence of workflow steps to be executed.
    # It provides a container for an array of WorkflowStep instances.
    class StepSequence < Dry::Struct
      # @!attribute [r] steps
      #   @return [Array<Tasker::WorkflowStep>] List of workflow steps in this sequence
      attribute :steps, Types::Array.default([].freeze)

      def find_step_by_name(name)
        Tasker::WorkflowStep.find_step_by_name(steps, name)
      end
    end
  end
end
