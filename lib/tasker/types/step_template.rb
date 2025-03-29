# frozen_string_literal: true

module Tasker
  module Types
    # StepTemplate defines the structure for workflow step templates
    #
    # @attr [String] dependent_system The system that this step depends on for execution
    # @attr [String] name The name identifier for this step template
    # @attr [String] description A human-readable description of what this step does
    # @attr [Boolean] default_retryable Whether this step can be retried by default
    # @attr [Integer] default_retry_limit The default maximum number of retry attempts
    # @attr [Boolean] skippable Whether this step can be skipped in the workflow
    # @attr [String, nil] depends_on_step Optional name of a step that must be completed before this one
    # @attr [Class] handler_class The class that implements the step's logic
    # @attr [Any, nil] handler_config Optional configuration for the step handler
    class StepTemplate < Dry::Struct
      attribute :dependent_system, Types::String
      attribute :name, Types::String
      attribute :description, Types::String
      attribute :depends_on_step, Types::String.optional.default(nil)
      attribute :default_retryable, Types::Bool.default(true)
      attribute :default_retry_limit, Types::Integer.default(3)
      attribute :skippable, Types::Bool.default(false)
      attribute :handler_class, Types::Class
      attribute :handler_config, Types::Any.optional.default(nil)
    end
  end
end
