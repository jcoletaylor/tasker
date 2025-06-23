# frozen_string_literal: true

# Tasker::Telemetry namespace for intelligent event-driven telemetry routing
#
# This module provides the strategic evolution of Tasker's telemetry architecture,
# transforming the existing solid TelemetrySubscriber foundation into a comprehensive,
# event-driven observability system that leverages our robust 40+ event pub/sub model.
#
# Components:
# - EventRouter: Intelligent routing core for event→telemetry mapping
# - EventMapping: Declarative configuration for routing decisions
# - SubscriberEnhancer: Evolution wrapper for existing TelemetrySubscriber
# - MetricsBackend: Thread-safe native metrics collection (Phase 4.2.2)
#
# Core Philosophy: PRESERVE all existing TelemetrySubscriber functionality while
# dramatically expanding observability through intelligent event routing.
#
# Usage:
#   # Configure intelligent event routing
#   Tasker::Telemetry::EventRouter.configure do |router|
#     router.map 'task.completed' => [:trace, :metrics]
#     router.map 'workflow.viable_steps_discovered' => [:trace, :metrics]
#     router.map 'observability.task.enqueue' => [:metrics]
#   end
#
#   # Evolution of existing TelemetrySubscriber (zero breaking changes)
#   enhanced_subscriber = Tasker::Telemetry::SubscriberEnhancer.new
#   enhanced_subscriber.subscribe_to_publisher(publisher)

# Explicitly require telemetry components for predictable loading
require_relative 'telemetry/event_mapping'
require_relative 'telemetry/event_router'

module Tasker
  module Telemetry
    # All telemetry components are now explicitly loaded above
    # This provides predictable loading order and avoids autoload complexity
  end
end
