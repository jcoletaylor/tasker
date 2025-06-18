# frozen_string_literal: true

module Tasker
  module Types
    # Configuration type for dependency graph calculation settings
    #
    # This configuration exposes previously hardcoded calculation constants
    # used in dependency graph analysis and bottleneck detection.
    #
    # @example Basic usage
    #   config = DependencyGraphConfig.new(
    #     impact_multipliers: { downstream_weight: 5, blocked_weight: 15 }
    #   )
    #
    # @example With all options
    #   config = DependencyGraphConfig.new(
    #     impact_multipliers: {
    #       downstream_weight: 5,
    #       blocked_weight: 15,
    #       path_length_weight: 10,
    #       completed_penalty: 15,
    #       blocked_penalty: 25,
    #       error_penalty: 30,
    #       retry_penalty: 10
    #     },
    #     severity_multipliers: {
    #       error_state: 2.0,
    #       exhausted_retry_bonus: 0.5,
    #       dependency_issue: 1.2
    #     },
    #     penalty_constants: {
    #       retry_instability: 3,
    #       non_retryable: 10,
    #       exhausted_retry: 20
    #     },
    #     severity_thresholds: {
    #       critical: 100,
    #       high: 50,
    #       medium: 20
    #     },
    #     duration_estimates: {
    #       base_step_seconds: 30,
    #       error_penalty_seconds: 60,
    #       retry_penalty_seconds: 30
    #     }
    #   )
    class DependencyGraphConfig < BaseConfig
      transform_keys(&:to_sym)

      # Impact multipliers for bottleneck scoring calculations
      #
      # These multipliers affect how different factors influence the final
      # bottleneck impact scores in RuntimeGraphAnalyzer.
      #
      # @!attribute [r] impact_multipliers
      #   @return [Hash<Symbol, Integer>] Impact calculation multipliers
      attribute :impact_multipliers, Types::Hash.schema(
        downstream_weight: Types::Integer.default(5),
        blocked_weight: Types::Integer.default(15),
        path_length_weight: Types::Integer.default(10),
        completed_penalty: Types::Integer.default(15),
        blocked_penalty: Types::Integer.default(25),
        error_penalty: Types::Integer.default(30),
        retry_penalty: Types::Integer.default(10)
      ).constructor { |value| value.respond_to?(:deep_symbolize_keys) ? value.deep_symbolize_keys : value }
       .default({
        downstream_weight: 5,
        blocked_weight: 15,
        path_length_weight: 10,
        completed_penalty: 15,
        blocked_penalty: 25,
        error_penalty: 30,
        retry_penalty: 10
      }.freeze)

      # Severity multipliers for state-based calculations
      #
      # These multipliers adjust impact scores based on step states
      # and execution conditions.
      #
      # @!attribute [r] severity_multipliers
      #   @return [Hash<Symbol, Float>] State severity multipliers
      attribute :severity_multipliers, Types::Hash.schema(
        error_state: Types::Float.default(2.0),
        exhausted_retry_bonus: Types::Float.default(0.5),
        dependency_issue: Types::Float.default(1.2)
      ).constructor { |value| value.respond_to?(:deep_symbolize_keys) ? value.deep_symbolize_keys : value }
       .default({
        error_state: 2.0,
        exhausted_retry_bonus: 0.5,
        dependency_issue: 1.2
      }.freeze)

      # Penalty constants for problematic step conditions
      #
      # These constants add penalty points for retry instability,
      # non-retryable issues, and exhausted retry attempts.
      #
      # @!attribute [r] penalty_constants
      #   @return [Hash<Symbol, Integer>] Penalty calculation constants
      attribute :penalty_constants, Types::Hash.schema(
        retry_instability: Types::Integer.default(3),
        non_retryable: Types::Integer.default(10),
        exhausted_retry: Types::Integer.default(20)
      ).constructor { |value| value.respond_to?(:deep_symbolize_keys) ? value.deep_symbolize_keys : value }
       .default({
        retry_instability: 3,
        non_retryable: 10,
        exhausted_retry: 20
      }.freeze)

      # Severity thresholds for impact score classification
      #
      # These thresholds determine when bottlenecks are classified as
      # Critical, High, Medium, or Low severity.
      #
      # @!attribute [r] severity_thresholds
      #   @return [Hash<Symbol, Integer>] Severity classification thresholds
      attribute :severity_thresholds, Types::Hash.schema(
        critical: Types::Integer.default(100),
        high: Types::Integer.default(50),
        medium: Types::Integer.default(20)
      ).constructor { |value| value.respond_to?(:deep_symbolize_keys) ? value.deep_symbolize_keys : value }
       .default({
        critical: 100,
        high: 50,
        medium: 20
      }.freeze)

      # Duration estimation constants for path analysis
      #
      # These constants are used for estimating execution times
      # and calculating path durations.
      #
      # @!attribute [r] duration_estimates
      #   @return [Hash<Symbol, Integer>] Duration estimation constants in seconds
      attribute :duration_estimates, Types::Hash.schema(
        base_step_seconds: Types::Integer.default(30),
        error_penalty_seconds: Types::Integer.default(60),
        retry_penalty_seconds: Types::Integer.default(30)
      ).constructor { |value| value.respond_to?(:deep_symbolize_keys) ? value.deep_symbolize_keys : value }
       .default({
        base_step_seconds: 30,
        error_penalty_seconds: 60,
        retry_penalty_seconds: 30
      }.freeze)
    end
  end
end
