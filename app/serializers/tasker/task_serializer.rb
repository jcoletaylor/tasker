# typed: false
# frozen_string_literal: true

# == Schema Information
#
# Table name: tasks
#
#  bypass_steps  :json
#  complete      :boolean          default(FALSE), not null
#  context       :jsonb
#  identity_hash :string(128)      not null
#  initiator     :string(128)
#  reason        :string(128)
#  requested_at  :datetime         not null
#  source_system :string(128)
#  status        :string(64)       not null
#  tags          :jsonb
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  named_task_id :integer          not null
#  task_id       :bigint           not null, primary key
#
# Indexes
#
#  index_tasks_on_identity_hash  (identity_hash) UNIQUE
#  tasks_context_idx             (context) USING gin
#  tasks_context_idx1            (context) USING gin
#  tasks_identity_hash_index     (identity_hash)
#  tasks_named_task_id_index     (named_task_id)
#  tasks_requested_at_index      (requested_at)
#  tasks_source_system_index     (source_system)
#  tasks_status_index            (status)
#  tasks_tags_idx                (tags) USING gin
#  tasks_tags_idx1               (tags) USING gin
#
# Foreign Keys
#
#  tasks_named_task_id_foreign  (named_task_id => named_tasks.named_task_id)
#

module Tasker
  class TaskSerializer < ActiveModel::Serializer
    attributes :task_id, :name, :namespace, :version, :full_name, :initiator, :source_system, :context, :reason,
               :bypass_steps, :tags, :requested_at, :complete, :status
    has_many :workflow_steps
    has_many :task_annotations

    # Conditional attribute for dependency analysis
    attribute :dependency_analysis, if: :include_dependency_analysis?

    def namespace
      object.named_task&.task_namespace&.name || 'default'
    end

    def version
      object.named_task&.version || '0.1.0'
    end

    def full_name
      "#{namespace}.#{object.named_task&.name}@#{version}"
    end

    # Check if dependency analysis should be included
    def include_dependency_analysis?
      instance_options[:include_dependencies] == true
    end

    # Generate dependency analysis
    def dependency_analysis
      # Get comprehensive dependency analysis from the runtime analyzer
      analysis = object.dependency_graph

      {
        dependency_graph: analysis[:dependency_graph],
        critical_paths: analysis[:critical_paths],
        parallelism_opportunities: analysis[:parallelism_opportunities],
        error_chains: analysis[:error_chains],
        bottlenecks: analysis[:bottlenecks],
        analysis_timestamp: Time.current.iso8601,
        task_execution_summary: build_execution_summary(analysis)
      }
    rescue StandardError => e
      # Graceful fallback if dependency analysis fails
      {
        error: "Dependency analysis failed: #{e.message}",
        analysis_timestamp: Time.current.iso8601
      }
    end

    private

    # Build a high-level execution summary from dependency analysis
    #
    # @param dependency_analysis [Hash] The full dependency analysis from RuntimeGraphAnalyzer
    # @return [Hash] High-level summary of task execution state and recommendations
    def build_execution_summary(dependency_analysis)
      graph = dependency_analysis[:dependency_graph]
      critical_paths = dependency_analysis[:critical_paths]
      bottlenecks = dependency_analysis[:bottlenecks]
      parallelism = dependency_analysis[:parallelism_opportunities]
      error_chains = dependency_analysis[:error_chains]

      {
        total_steps: graph[:nodes]&.size || 0,
        total_dependencies: graph[:edges]&.size || 0,
        dependency_levels: graph[:dependency_levels]&.keys&.size || 0,
        longest_path_length: critical_paths[:longest_path_length] || 0,
        critical_bottlenecks_count: bottlenecks[:critical_bottlenecks]&.size || 0,
        error_chains_count: error_chains[:error_chains]&.size || 0,
        parallelism_efficiency: parallelism[:overall_efficiency] || 0,
        overall_health: determine_overall_health(dependency_analysis),
        recommendations: build_recommendations(dependency_analysis)
      }
    end

    # Determine overall task health based on dependency analysis
    #
    # @param dependency_analysis [Hash] The full dependency analysis
    # @return [String] Health status: 'healthy', 'warning', 'critical'
    def determine_overall_health(dependency_analysis)
      bottlenecks = dependency_analysis[:bottlenecks]
      error_chains = dependency_analysis[:error_chains]

      critical_bottlenecks_count = bottlenecks[:critical_bottlenecks]&.size || 0
      error_count = error_chains[:error_chains]&.size || 0

      if critical_bottlenecks_count.positive? || error_count.positive?
        'critical'
      elsif bottlenecks[:bottlenecks].is_a?(Array) && bottlenecks[:bottlenecks].any? { |b| b[:severity] == 'High' }
        'warning'
      else
        'healthy'
      end
    end

    # Build actionable recommendations based on dependency analysis
    #
    # @param dependency_analysis [Hash] The full dependency analysis
    # @return [Array<String>] Array of recommendation strings
    def build_recommendations(dependency_analysis)
      recommendations = []

      bottlenecks = dependency_analysis[:bottlenecks]
      error_chains = dependency_analysis[:error_chains]
      parallelism = dependency_analysis[:parallelism_opportunities]

      # Bottleneck recommendations
      if bottlenecks[:critical_bottlenecks].is_a?(Array) && bottlenecks[:critical_bottlenecks].any?
        recommendations << 'Address critical bottlenecks to unblock task execution'
      end

      # Error chain recommendations
      if error_chains[:error_chains].is_a?(Array) && error_chains[:error_chains].any?
        recommendations << 'Resolve error chains to prevent further failures'
      end

      # Parallelism recommendations
      if parallelism[:overall_efficiency] && parallelism[:overall_efficiency] < 0.5
        recommendations << 'Consider optimizing step dependencies to improve parallelism'
      end

      # Default recommendation if no issues found
      recommendations << 'Task execution appears healthy' if recommendations.empty?

      recommendations
    end
  end
end
