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
# - MetricTypes: Counter, Gauge, Histogram with atomic thread-safe operations
# - MetricsBackend: Thread-safe native metrics collection with EventRouter integration
# - SubscriberEnhancer: Evolution wrapper for existing TelemetrySubscriber (Phase 4.2.3)
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
#   # Direct metrics collection with thread-safe operations
#   backend = Tasker::Telemetry::MetricsBackend.instance
#   backend.counter('api_requests_total', endpoint: '/tasks').increment
#   backend.gauge('active_connections').set(42)
#   backend.histogram('request_duration_seconds').observe(0.125)
#
#   # Automatic event-driven metrics via EventRouter integration
#   router.route_event('task.completed', { task_id: '123', duration: 2.5 })
#
#   # Evolution of existing TelemetrySubscriber (zero breaking changes)
#   enhanced_subscriber = Tasker::Telemetry::SubscriberEnhancer.new  # Phase 4.2.3
#   enhanced_subscriber.subscribe_to_publisher(publisher)

# Explicitly require telemetry components for predictable loading
require_relative 'telemetry/metric_types'
require_relative 'telemetry/event_mapping'
require_relative 'telemetry/event_router'
require_relative 'telemetry/metrics_backend'
require_relative 'telemetry/prometheus_exporter'
require_relative 'telemetry/export_coordinator'
require_relative 'telemetry/plugin_registry'

# Require the MetricsSubscriber for automatic event-to-metrics bridging
require_relative 'events/subscribers/metrics_subscriber'

module Tasker
  module Telemetry
    # All telemetry components are now explicitly loaded above
    # This provides predictable loading order and avoids autoload complexity
  end
end
