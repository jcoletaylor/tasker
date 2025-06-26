# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Telemetry::EventRouter, type: :model do
  let(:router) { described_class.instance }

  # Reset router state before each test to ensure isolation
  around do |example|
    original_mappings = router.mappings.dup
    original_trace_events = router.trace_events.dup
    original_metrics_events = router.metrics_events.dup
    original_log_events = router.log_events.dup

    example.run

    # Restore original state
    router.instance_variable_set(:@mappings, original_mappings)
    router.instance_variable_set(:@trace_events, original_trace_events)
    router.instance_variable_set(:@metrics_events, original_metrics_events)
    router.instance_variable_set(:@log_events, original_log_events)
  end

  describe '.instance' do
    it 'returns a singleton instance' do
      instance1 = described_class.instance
      instance2 = described_class.instance

      expect(instance1).to be(instance2)
    end

    it 'loads default mappings on initialization' do
      # Reset and check defaults are loaded
      router.reset!

      # Check some expected default mappings
      expect(router.mappings).to have_key('task.completed')
      expect(router.mappings).to have_key('step.failed')
      expect(router.mappings).to have_key('workflow.viable_steps_discovered')
    end
  end

  describe '.configure' do
    it 'yields the router instance for configuration' do
      described_class.configure do |config_router|
        expect(config_router).to be(router)
        config_router.map('test.event', backends: [:trace])
      end

      expect(router.mappings).to have_key('test.event')
    end

    it 'returns the router instance' do
      result = described_class.configure { |r| r.map('test', backends: [:trace]) }
      expect(result).to be(router)
    end
  end

  describe '#map' do
    it 'creates a mapping with explicit backends parameter' do
      mapping = router.map('task.test', backends: %i[trace metrics])

      expect(mapping.event_name).to eq('task.test')
      expect(mapping.backends).to eq(%i[trace metrics])
      expect(router.mappings['task.test']).to eq(mapping)
    end

    it 'creates a mapping with keyword arguments' do
      mapping = router.map('step.test', backends: [:metrics], sampling_rate: 0.5)

      expect(mapping.event_name).to eq('step.test')
      expect(mapping.backends).to eq([:metrics])
      expect(mapping.sampling_rate).to eq(0.5)
    end

    it 'updates backend event lists when mapping is created' do
      router.map('trace.only', backends: [:trace])
      router.map('metrics.only', backends: [:metrics])
      router.map('both.event', backends: %i[trace metrics])

      expect(router.trace_events).to include('trace.only', 'both.event')
      expect(router.metrics_events).to include('metrics.only', 'both.event')
    end

    it 'handles string and symbol event names' do
      mapping1 = router.map(:symbol_event, backends: [:trace])
      mapping2 = router.map('string_event', backends: [:trace])

      expect(mapping1.event_name).to eq('symbol_event')
      expect(mapping2.event_name).to eq('string_event')
    end

    it 'accepts all mapping options' do
      mapping = router.map(
        'complex.event',
        backends: %i[trace metrics],
        enabled: false,
        sampling_rate: 0.1,
        priority: :high,
        metadata: { source: 'test' }
      )

      expect(mapping.enabled).to be(false)
      expect(mapping.sampling_rate).to eq(0.1)
      expect(mapping.priority).to eq(:high)
      expect(mapping.metadata).to eq({ source: 'test' })
    end
  end

  describe '#mapping_for' do
    before do
      router.map('test.event', backends: [:trace])
    end

    it 'returns the mapping for an existing event' do
      mapping = router.mapping_for('test.event')

      expect(mapping).to be_a(Tasker::Telemetry::EventMapping)
      expect(mapping.event_name).to eq('test.event')
    end

    it 'returns nil for non-existent events' do
      mapping = router.mapping_for('nonexistent.event')

      expect(mapping).to be_nil
    end

    it 'handles string and symbol event names' do
      mapping1 = router.mapping_for('test.event')
      mapping2 = router.mapping_for(:test_event)

      expect(mapping1).not_to be_nil
      expect(mapping2).to be_nil # Different event name
    end
  end

  describe '#mapping_exists?' do
    before do
      router.map('test.event', backends: [:trace])
    end

    it 'returns true for existing events' do
      expect(router.mapping_exists?('test.event')).to be(true)
    end

    it 'returns false for non-existent events' do
      expect(router.mapping_exists?('nonexistent.event')).to be(false)
    end

    it 'handles string and symbol event names consistently' do
      expect(router.mapping_exists?('test.event')).to be(true)
      expect(router.mapping_exists?(:test_event)).to be(false) # Different event name
    end
  end

  describe '#routes_to_traces?' do
    before do
      router.map('trace.event', backends: [:trace])
      router.map('metrics.event', backends: [:metrics])
      router.map('disabled.event', backends: [:trace], enabled: false)
      router.map('sampled.event', backends: [:trace], sampling_rate: 0.0)
    end

    it 'returns true for events that route to traces and are active' do
      expect(router.routes_to_traces?('trace.event')).to be(true)
    end

    it 'returns false for events that do not route to traces' do
      expect(router.routes_to_traces?('metrics.event')).to be(false)
    end

    it 'returns false for disabled events' do
      expect(router.routes_to_traces?('disabled.event')).to be(false)
    end

    it 'returns false for events with zero sampling rate' do
      expect(router.routes_to_traces?('sampled.event')).to be(false)
    end

    it 'returns false for non-existent events' do
      expect(router.routes_to_traces?('nonexistent.event')).to be(false)
    end
  end

  describe '#routes_to_metrics?' do
    before do
      router.map('metrics.event', backends: [:metrics])
      router.map('trace.event', backends: [:trace])
      router.map('disabled.event', backends: [:metrics], enabled: false)
    end

    it 'returns true for events that route to metrics and are active' do
      expect(router.routes_to_metrics?('metrics.event')).to be(true)
    end

    it 'returns false for events that do not route to metrics' do
      expect(router.routes_to_metrics?('trace.event')).to be(false)
    end

    it 'returns false for disabled events' do
      expect(router.routes_to_metrics?('disabled.event')).to be(false)
    end
  end

  describe '#routes_to_logs?' do
    before do
      router.map('log.event', backends: [:logs])
      router.map('trace.event', backends: [:trace])
    end

    it 'returns true for events that route to logs and are active' do
      expect(router.routes_to_logs?('log.event')).to be(true)
    end

    it 'returns false for events that do not route to logs' do
      expect(router.routes_to_logs?('trace.event')).to be(false)
    end
  end

  describe '#events_for_backend' do
    before do
      router.map('trace.event', backends: [:trace])
      router.map('metrics.event', backends: [:metrics])
      router.map('log.event', backends: [:logs])
      router.map('multi.event', backends: %i[trace metrics])
    end

    it 'returns trace events for :trace backend' do
      events = router.events_for_backend(:trace)
      expect(events).to include('trace.event', 'multi.event')
      expect(events).not_to include('metrics.event', 'log.event')
    end

    it 'returns metrics events for :metrics backend' do
      events = router.events_for_backend(:metrics)
      expect(events).to include('metrics.event', 'multi.event')
      expect(events).not_to include('trace.event', 'log.event')
    end

    it 'returns log events for :logs backend' do
      events = router.events_for_backend(:logs)
      expect(events).to include('log.event')
      expect(events).not_to include('trace.event', 'metrics.event')
    end

    it 'handles plural forms' do
      expect(router.events_for_backend(:traces)).to eq(router.events_for_backend(:trace))
      expect(router.events_for_backend(:metrics)).to eq(router.events_for_backend(:metric))
    end

    it 'raises error for unknown backends' do
      expect { router.events_for_backend(:unknown) }.to raise_error(
        ArgumentError, /Unknown backend type: :unknown/
      )
    end
  end

  describe '#routing_stats' do
    before do
      router.reset! # Start with defaults
      router.map('high.priority', backends: [:trace], priority: :high)
      router.map('sampled.event', backends: [:metrics], sampling_rate: 0.5)
      router.map('disabled.event', backends: [:trace], enabled: false)
    end

    it 'returns comprehensive routing statistics' do
      stats = router.routing_stats

      expect(stats).to include(
        :total_mappings,
        :trace_events,
        :metrics_events,
        :log_events,
        :enabled_mappings,
        :high_priority,
        :sampled_mappings
      )

      expect(stats[:total_mappings]).to be > 0
      expect(stats[:high_priority]).to be >= 1
      expect(stats[:sampled_mappings]).to be >= 1
    end
  end

  describe '#reset!' do
    it 'clears all mappings and reloads defaults' do
      # Add custom mapping
      router.map('custom.event', backends: [:trace])
      expect(router.mappings).to have_key('custom.event')

      # Reset
      router.reset!

      # Custom mapping should be gone, defaults should be back
      expect(router.mappings).not_to have_key('custom.event')
      expect(router.mappings).to have_key('task.completed') # Default mapping
    end

    it 'resets all backend event lists' do
      # Add custom events
      router.map('custom.trace', backends: [:trace])
      router.map('custom.metrics', backends: [:metrics])

      # Reset
      router.reset!

      # Should not contain custom events
      expect(router.trace_events).not_to include('custom.trace')
      expect(router.metrics_events).not_to include('custom.metrics')
    end
  end

  describe '#configured_events' do
    it 'returns all configured event names' do
      router.reset!
      router.map('custom.event', backends: [:trace])

      events = router.configured_events

      expect(events).to include('task.completed')  # Default
      expect(events).to include('custom.event')    # Custom
      expect(events).to be_an(Array)
    end
  end

  describe '#bulk_configure' do
    it 'configures multiple mappings with array backends' do
      config = {
        'event1' => [:trace],
        'event2' => [:metrics],
        'event3' => %i[trace metrics]
      }

      mappings = router.bulk_configure(config)

      expect(mappings.size).to eq(3)
      expect(router.mappings).to have_key('event1')
      expect(router.mappings).to have_key('event2')
      expect(router.mappings).to have_key('event3')
    end

    it 'configures multiple mappings with hash options' do
      config = {
        'event1' => { backends: [:trace], sampling_rate: 0.1 },
        'event2' => { backends: [:metrics], priority: :high }
      }

      mappings = router.bulk_configure(config)

      expect(mappings.size).to eq(2)
      expect(router.mapping_for('event1').sampling_rate).to eq(0.1)
      expect(router.mapping_for('event2').priority).to eq(:high)
    end

    it 'configures mappings with single backend symbols' do
      config = {
        'event1' => :trace,
        'event2' => :metrics
      }

      mappings = router.bulk_configure(config)

      expect(mappings.size).to eq(2)
      expect(router.mapping_for('event1').backends).to eq([:trace])
      expect(router.mapping_for('event2').backends).to eq([:metrics])
    end

    it 'returns empty array for nil or empty config' do
      expect(router.bulk_configure(nil)).to eq([])
      expect(router.bulk_configure({})).to eq([])
    end

    it 'raises error for invalid config values' do
      config = { 'event1' => 42 } # Invalid type

      expect { router.bulk_configure(config) }.to raise_error(
        ArgumentError, /Invalid config for event1: 42/
      )
    end
  end

  describe 'default mappings' do
    before { router.reset! }

    it 'preserves all current TelemetrySubscriber events with both traces and metrics' do
      # Current 8 events that must be preserved for zero breaking changes
      current_events = [
        'task.initialize_requested',
        'task.start_requested',
        'task.completed',
        'task.failed',
        'step.execution_requested',
        'step.completed',
        'step.failed',
        'step.retry_requested'
      ]

      current_events.each do |event|
        mapping = router.mapping_for(event)
        expect(mapping).not_to be_nil, "Missing mapping for #{event}"
        expect(mapping.routes_to_traces?).to be(true), "#{event} should route to traces"
        expect(mapping.routes_to_metrics?).to be(true), "#{event} should route to metrics"
      end
    end

    it 'includes enhanced lifecycle events with intelligent routing' do
      # Enhanced events for expanded observability
      enhanced_events = {
        'workflow.viable_steps_discovered' => %i[trace metrics],
        'observability.task.enqueue' => [:metrics],
        'observability.step.backoff' => %i[trace metrics],
        'step.before_handle' => [:trace]
      }

      enhanced_events.each do |event, expected_backends|
        mapping = router.mapping_for(event)
        expect(mapping).not_to be_nil, "Missing mapping for #{event}"

        expected_backends.each do |backend|
          case backend
          when :trace
            expect(mapping.routes_to_traces?).to be(true), "#{event} should route to traces"
          when :metrics
            expect(mapping.routes_to_metrics?).to be(true), "#{event} should route to metrics"
          when :logs
            expect(mapping.routes_to_logs?).to be(true), "#{event} should route to logs"
          end
        end
      end
    end

    it 'includes future-ready events with appropriate sampling' do
      # Future events with sampling for performance
      future_events = [
        'database.query_executed',
        'dependency.resolved',
        'batch.step_execution'
      ]

      future_events.each do |event|
        mapping = router.mapping_for(event)
        expect(mapping).not_to be_nil, "Missing mapping for #{event}"
      end

      # Check specific sampling for performance-sensitive events
      db_mapping = router.mapping_for('database.query_executed')
      expect(db_mapping.sampling_rate).to eq(0.1) # 10% sampling for database queries
    end

    it 'includes high-priority operational events' do
      high_priority_events = [
        'observability.task.enqueue',
        'observability.step.max_retries_reached',
        'memory.spike_detected',
        'performance.slow_operation'
      ]

      high_priority_events.each do |event|
        mapping = router.mapping_for(event)
        expect(mapping).not_to be_nil, "Missing mapping for #{event}"
        expect(mapping.priority).to be_in(%i[high critical]), "#{event} should have high/critical priority"
      end
    end
  end

  describe 'integration with existing patterns' do
    it 'follows singleton pattern like HandlerFactory' do
      expect(described_class).to include(Singleton)
    end

    it 'provides thread-safe access to mappings' do
      # Test concurrent access (basic thread safety)
      threads = Array.new(10) do |i|
        Thread.new do
          router.map("thread.event.#{i}", backends: [:trace])
          router.mapping_for("thread.event.#{i}")
        end
      end

      results = threads.map(&:value)
      expect(results).to all(be_a(Tasker::Telemetry::EventMapping))
    end
  end
end
