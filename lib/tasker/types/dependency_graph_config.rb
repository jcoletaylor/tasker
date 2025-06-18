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
    #     weight_multipliers: { complexity: 1.5, priority: 2.0 }
    #   )
    #
    # @example With all options
    #   config = DependencyGraphConfig.new(
    #     weight_multipliers: {
    #       complexity: 1.5,
    #       priority: 2.0,
    #       depth: 1.2,
    #       fan_out: 0.8
    #     },
    #     threshold_constants: {
    #       bottleneck_threshold: 0.8,
    #       critical_path_threshold: 0.9,
    #       warning_threshold: 0.6
    #     },
    #     calculation_limits: {
    #       max_depth: 50,
    #       max_nodes: 1000,
    #       timeout_seconds: 30
    #     }
    #   )
    class DependencyGraphConfig < BaseConfig
      transform_keys(&:to_sym)

      # Weight multipliers for different aspects of dependency calculations
      #
      # These multipliers affect how different factors influence the final
      # bottleneck impact scores and dependency analysis results.
      #
      # @!attribute [r] weight_multipliers
      #   @return [Hash<Symbol, Float>] Weight multipliers for calculations
      attribute :weight_multipliers, Types::Hash.schema(
        complexity: Types::Float.default(1.5),
        priority: Types::Float.default(2.0),
        depth: Types::Float.default(1.2),
        fan_out: Types::Float.default(0.8)
      ).default({
        complexity: 1.5,
        priority: 2.0,
        depth: 1.2,
        fan_out: 0.8
      }.freeze)

      # Threshold constants for various analysis decisions
      #
      # These thresholds determine when steps or paths are considered
      # critical, bottlenecks, or worthy of warnings.
      #
      # @!attribute [r] threshold_constants
      #   @return [Hash<Symbol, Float>] Threshold values for analysis
      attribute :threshold_constants, Types::Hash.schema(
        bottleneck_threshold: Types::Float.default(0.8),
        critical_path_threshold: Types::Float.default(0.9),
        warning_threshold: Types::Float.default(0.6)
      ).default({
        bottleneck_threshold: 0.8,
        critical_path_threshold: 0.9,
        warning_threshold: 0.6
      }.freeze)

      # Calculation limits to prevent runaway computations
      #
      # These limits ensure that dependency graph calculations remain
      # performant even with very large or complex workflows.
      #
      # @!attribute [r] calculation_limits
      #   @return [Hash<Symbol, Integer>] Limits for calculations
      attribute :calculation_limits, Types::Hash.schema(
        max_depth: Types::Integer.default(50),
        max_nodes: Types::Integer.default(1000),
        timeout_seconds: Types::Integer.default(30)
      ).default({
        max_depth: 50,
        max_nodes: 1000,
        timeout_seconds: 30
      }.freeze)
    end
  end
end
