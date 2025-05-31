# frozen_string_literal: true

require 'active_support/concern'

module Tasker
  module Concerns
    # OrchestrationPublisher provides event publishing capabilities for orchestration components
    #
    # This concern allows orchestration components to publish events through the
    # centralized orchestrator without needing to manage the orchestrator instance directly.
    # It provides a clean, consistent interface for event publishing throughout the
    # orchestration system.
    module OrchestrationPublisher
      extend ActiveSupport::Concern

      included do
        # Initialize with orchestrator as event publisher
        #
        # @param orchestrator [Tasker::Orchestration::Orchestrator] The orchestrator that acts as event publisher
        def initialize(orchestrator = nil)
          @orchestrator = orchestrator || Tasker::Orchestration::Orchestrator.instance
        end
      end

      private

      # Publish an event through the orchestrator
      #
      # This method provides a clean interface for publishing events without
      # requiring orchestration components to manage the orchestrator directly.
      #
      # @param event_constant [String] The event constant (e.g., Tasker::Constants::StepEvents::COMPLETED)
      # @param payload [Hash] The event payload
      def publish_event(event_constant, payload = {})
        @orchestrator.publish(event_constant, payload.merge(timestamp: Time.current))
      rescue StandardError => e
        Rails.logger.error("Failed to publish event #{event_constant}: #{e.message}")
      end
    end
  end
end
