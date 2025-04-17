# frozen_string_literal: true

module Tasker
  module Types
    # StepTemplate defines the structure for workflow step templates
    #
    # A step template provides the blueprint for creating specific workflow steps
    # in a task's sequence. It defines the behavior, dependencies, and configuration
    # for steps of a particular type.
    class StepTemplate < Dry::Struct
      # @!attribute [r] dependent_system
      #   @return [String] The system that this step depends on for execution
      attribute :dependent_system, Types::Strict::String

      # @!attribute [r] name
      #   @return [String] The name identifier for this step template
      attribute :name, Types::Strict::String

      # @!attribute [r] description
      #   @return [String] A human-readable description of what this step does
      attribute :description, Types::String

      # @!attribute [r] default_retryable
      #   @return [Boolean] Whether this step can be retried by default
      attribute :default_retryable, Types::Bool.default(true)

      # @!attribute [r] default_retry_limit
      #   @return [Integer] The default maximum number of retry attempts
      attribute :default_retry_limit, Types::Integer.default(3)

      # @!attribute [r] skippable
      #   @return [Boolean] Whether this step can be skipped in the workflow
      attribute :skippable, Types::Bool.default(false)

      # @!attribute [r] handler_class
      #   @return [Class] The class that implements the step's logic
      attribute :handler_class, Types::Class

      # @!attribute [r] handler_config
      #   @return [Object, nil] Optional configuration for the step handler
      attribute :handler_config, Types::Any.optional.default(nil)

      # @!attribute [r] depends_on_step
      #   @return [String, nil] Optional name of a step that must be completed before this one
      attribute :depends_on_step, Types::String.optional.default(nil)

      # @!attribute [r] depends_on_steps
      #   @return [Array<String>] Names of steps that must be completed before this one
      attribute :depends_on_steps, Types.Array(Types::String).default([].freeze)

      # Returns all dependency step names as a single array
      #
      # @return [Array<String>] All step dependencies
      def all_dependencies
        [depends_on_step, *depends_on_steps].compact.uniq
      end
    end
  end
end
