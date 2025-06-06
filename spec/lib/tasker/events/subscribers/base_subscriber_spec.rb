# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Events::Subscribers::BaseSubscriber do
  let(:publisher) { Tasker::Events::Publisher.instance }
  let(:captured_events) { [] }

  # Create a test subscriber class for testing
  let(:test_subscriber_class) do
    Class.new(described_class) do
      # Use actual constants instead of symbols to avoid mapping
      subscribe_to Tasker::Constants::TaskEvents::COMPLETED,
                   Tasker::Constants::StepEvents::FAILED,
                   'custom.event'

      attr_reader :received_events

      def initialize
        super
        @received_events = []
      end

      def handle_task_completed(event)
        @received_events << { type: 'task_completed', event: event }
      end

      def handle_step_failed(event)
        @received_events << { type: 'step_failed', event: event }
      end

      def handle_custom_event(event)
        @received_events << { type: 'custom_event', event: event }
      end
    end
  end

  before do
    # Clear any existing subscriptions
    captured_events.clear
  end

  describe 'class methods' do
    describe '.subscribe_to' do
      it 'registers events for subscription' do
        expect(test_subscriber_class.subscribed_events).to include(
          Tasker::Constants::TaskEvents::COMPLETED,
          Tasker::Constants::StepEvents::FAILED,
          'custom.event'
        )
      end

      it 'can be called multiple times to add events' do
        dynamic_class = Class.new(described_class) do
          subscribe_to 'event1'
          subscribe_to 'event2', 'event3'
        end

        expect(dynamic_class.subscribed_events).to include('event1', 'event2', 'event3')
      end
    end

    describe '.filter_events' do
      it 'sets an event filter' do
        filtered_class = Class.new(described_class) do
          subscribe_to :task_completed, :step_failed
          filter_events { |event_name| event_name.include?('task') }
        end

        expect(filtered_class.event_filter).to be_a(Proc)
      end
    end

    describe '.subscribe' do
      it 'creates an instance and subscribes it to the publisher' do
        subscriber = test_subscriber_class.subscribe(publisher)
        expect(subscriber).to be_a(test_subscriber_class)
        expect(subscriber.received_events).to eq([])
      end
    end
  end

  describe 'instance methods' do
    let(:subscriber) { test_subscriber_class.new }

    describe '#event_subscriptions' do
      it 'builds a mapping of event constants to handler methods' do
        subscriptions = subscriber.send(:event_subscriptions)

        expect(subscriptions).to include(
          Tasker::Constants::TaskEvents::COMPLETED => :handle_task_completed,
          Tasker::Constants::StepEvents::FAILED => :handle_step_failed,
          'custom.event' => :handle_custom_event
        )
      end

      it 'warns about missing handler methods' do
        incomplete_class = Class.new(described_class) do
          subscribe_to 'missing.handler'
        end

        expect(Rails.logger).to receive(:warn).with(/Handler method handle_missing_handler not found/)
        incomplete_class.new.send(:event_subscriptions)
      end
    end

    describe '#generate_handler_method_name' do
      it 'generates correct handler method names' do
        expect(subscriber.send(:generate_handler_method_name, 'task.completed')).to eq(:handle_task_completed)
        expect(subscriber.send(:generate_handler_method_name, 'custom.event')).to eq(:handle_custom_event)
        expect(subscriber.send(:generate_handler_method_name,
                               'order.payment.failed')).to eq(:handle_order_payment_failed)
      end
    end

    describe '#safe_get' do
      let(:event) { { task_id: '123', 'step_name' => 'test_step' } }

      it 'safely accesses hash keys with symbols' do
        expect(subscriber.send(:safe_get, event, :task_id)).to eq('123')
      end

      it 'safely accesses hash keys with strings' do
        expect(subscriber.send(:safe_get, event, 'step_name')).to eq('test_step')
      end

      it 'returns default for missing keys' do
        expect(subscriber.send(:safe_get, event, :missing_key, 'default')).to eq('default')
      end

      it 'handles nil events gracefully' do
        expect(subscriber.send(:safe_get, nil, :any_key, 'default')).to eq('default')
      end
    end

    describe '#extract_core_attributes' do
      let(:event) do
        {
          task_id: 'task-123',
          step_id: 'step-456',
          timestamp: Time.current,
          custom_field: 'value'
        }
      end

      it 'extracts common event attributes' do
        attributes = subscriber.send(:extract_core_attributes, event)

        expect(attributes).to include(
          task_id: 'task-123',
          step_id: 'step-456'
        )
        expect(attributes[:event_timestamp]).to be_present
      end

      it 'handles missing attributes gracefully' do
        minimal_event = { task_id: 'task-123' }
        attributes = subscriber.send(:extract_core_attributes, minimal_event)

        expect(attributes[:task_id]).to eq('task-123')
        expect(attributes[:step_id]).to be_nil
        expect(attributes[:event_timestamp]).to be_present
      end
    end
  end

  describe 'integration with event system' do
    let(:subscriber) { test_subscriber_class.subscribe(publisher) }

    before do
      # Subscribe the test subscriber
      subscriber
    end

    it 'receives and handles task completed events' do
      event_payload = { task_id: 'task-123', task_name: 'test_task' }

      # Publish a task completed event
      publisher.publish(Tasker::Constants::TaskEvents::COMPLETED, event_payload)

      # Verify the subscriber received and handled the event
      expect(subscriber.received_events.length).to eq(1)
      received = subscriber.received_events.first
      expect(received[:type]).to eq('task_completed')
      expect(received[:event][:task_id]).to eq('task-123')
    end

    it 'receives and handles step failed events' do
      event_payload = { task_id: 'task-123', step_id: 'step-456', error_message: 'Test error' }

      # Publish a step failed event
      publisher.publish(Tasker::Constants::StepEvents::FAILED, event_payload)

      # Verify the subscriber received and handled the event
      expect(subscriber.received_events.length).to eq(1)
      received = subscriber.received_events.first
      expect(received[:type]).to eq('step_failed')
      expect(received[:event][:error_message]).to eq('Test error')
    end

    it 'receives and handles custom events' do
      event_payload = { order_id: 'order-789', status: 'processed' }

      # Publish a custom event
      publisher.publish('custom.event', event_payload)

      # Verify the subscriber received and handled the event
      expect(subscriber.received_events.length).to eq(1)
      received = subscriber.received_events.first
      expect(received[:type]).to eq('custom_event')
      expect(received[:event][:order_id]).to eq('order-789')
    end

    it 'ignores events not subscribed to' do
      # Publish an event we're not subscribed to
      publisher.publish(Tasker::Constants::TaskEvents::START_REQUESTED, { task_id: 'task-123' })

      # Should not receive this event
      expect(subscriber.received_events).to be_empty
    end
  end

  describe 'event filtering' do
    let(:filtered_subscriber_class) do
      Class.new(described_class) do
        subscribe_to Tasker::Constants::TaskEvents::COMPLETED, Tasker::Constants::TaskEvents::FAILED
        filter_events { |event_name| event_name.include?('completed') }

        attr_reader :received_events

        def initialize
          super
          @received_events = []
        end

        def handle_task_completed(event)
          @received_events << event
        end

        def handle_task_failed(event)
          @received_events << event
        end
      end
    end

    it 'applies event filters during subscription' do
      subscriber = filtered_subscriber_class.subscribe(publisher)

      # Publish both events
      publisher.publish(Tasker::Constants::TaskEvents::COMPLETED, { task_id: 'task-123' })
      publisher.publish(Tasker::Constants::TaskEvents::FAILED, { task_id: 'task-456' })

      # Should only receive the completed event (filter matches 'completed' in constant name)
      expect(subscriber.received_events.length).to eq(1)
      expect(subscriber.received_events.first[:task_id]).to eq('task-123')
    end
  end

  describe 'inheritance and customization' do
    let(:custom_subscriber_class) do
      Class.new(described_class) do
        subscribe_to Tasker::Constants::TaskEvents::COMPLETED

        attr_reader :processed_events

        def initialize
          super
          @processed_events = []
        end

        # Override event subscription mapping
        def event_subscriptions
          {
            Tasker::Constants::TaskEvents::COMPLETED => :custom_handler
          }
        end

        # Custom handler with different naming
        def custom_handler(event)
          @processed_events << { custom: true, event: event }
        end

        # Override event filtering
        def should_process_event?(event_constant)
          # Only process events with 'completed' in the name
          event_constant.to_s.include?('completed')
        end
      end
    end

    it 'allows customization of subscription mapping' do
      subscriber = custom_subscriber_class.subscribe(publisher)

      publisher.publish(Tasker::Constants::TaskEvents::COMPLETED, { task_id: 'task-123' })

      expect(subscriber.processed_events.length).to eq(1)
      expect(subscriber.processed_events.first[:custom]).to be true
    end

    it 'allows customization of subscription mapping' do
      # Create a custom subscriber with overridden event_subscriptions
      custom_subscriber_class = Class.new(described_class) do
        def event_subscriptions
          { 'CustomEvent' => :handle_custom }
        end

        def handle_custom(event); end
      end

      subscriber = custom_subscriber_class.new
      expect(subscriber.event_subscriptions).to eq({ 'CustomEvent' => :handle_custom })
    end
  end

  # ===============================
  # METRICS COLLECTION HELPERS TESTS
  # ===============================

  describe 'metrics collection helpers' do
    let(:subscriber) { described_class.new }

    describe '#extract_timing_metrics' do
      let(:timing_event) do
        {
          execution_duration: 45.7,
          started_at: 2.minutes.ago,
          completed_at: Time.current,
          total_steps: 5,
          completed_steps: 4,
          failed_steps: 1
        }
      end

      it 'extracts timing metrics with proper types' do
        metrics = subscriber.send(:extract_timing_metrics, timing_event)

        expect(metrics[:execution_duration]).to eq(45.7)
        expect(metrics[:step_count]).to eq(5)
        expect(metrics[:completed_steps]).to eq(4)
        expect(metrics[:failed_steps]).to eq(1)
        expect(metrics[:started_at]).to be_present
        expect(metrics[:completed_at]).to be_present
      end

      it 'provides defaults for missing values' do
        minimal_event = { execution_duration: '30.5' }
        metrics = subscriber.send(:extract_timing_metrics, minimal_event)

        expect(metrics[:execution_duration]).to eq(30.5)
        expect(metrics[:step_count]).to eq(0)
        expect(metrics[:completed_steps]).to eq(0)
        expect(metrics[:failed_steps]).to eq(0)
      end
    end

    describe '#extract_error_metrics' do
      let(:error_event) do
        {
          error_message: 'Connection timeout',
          exception_class: 'Net::TimeoutError',
          attempt_number: 2,
          retry_limit: 3,
          retryable: true
        }
      end

      it 'extracts error metrics with categorization' do
        metrics = subscriber.send(:extract_error_metrics, error_event)

        expect(metrics[:error_message]).to eq('Connection timeout')
        expect(metrics[:error_class]).to eq('Net::TimeoutError')
        expect(metrics[:error_type]).to eq('timeout')
        expect(metrics[:attempt_number]).to eq(2)
        expect(metrics[:is_retryable]).to be(true)
        expect(metrics[:final_failure]).to be(false)
      end

      it 'detects final failures' do
        final_error_event = error_event.merge(attempt_number: 3, retry_limit: 3)
        metrics = subscriber.send(:extract_error_metrics, final_error_event)

        expect(metrics[:final_failure]).to be(true)
      end

      it 'categorizes different error types' do
        test_cases = [
          { exception_class: 'Net::TimeoutError', expected: 'timeout' },
          { exception_class: 'ConnectionError', expected: 'network' },
          { exception_class: 'NotFoundError', expected: 'not_found' },
          { exception_class: 'UnauthorizedError', expected: 'auth' },
          { exception_class: 'RateLimitError', expected: 'rate_limit' },
          { exception_class: 'BadRequestError', expected: 'client_error' },
          { exception_class: 'InternalServerError', expected: 'server_error' },
          { exception_class: 'StandardError', expected: 'runtime' },
          { exception_class: 'WeirdCustomError', expected: 'other' }
        ]

        test_cases.each do |test_case|
          event = { exception_class: test_case[:exception_class] }
          metrics = subscriber.send(:extract_error_metrics, event)
          expect(metrics[:error_type]).to eq(test_case[:expected])
        end
      end
    end

    describe '#extract_performance_metrics' do
      let(:performance_event) do
        {
          memory_usage: 1024,
          cpu_time: 2.5,
          queue_time: 0.1,
          processing_time: 1.8,
          retry_delay: 5.0
        }
      end

      it 'extracts performance metrics with type conversion' do
        metrics = subscriber.send(:extract_performance_metrics, performance_event)

        expect(metrics[:memory_usage]).to eq(1024)
        expect(metrics[:cpu_time]).to eq(2.5)
        expect(metrics[:queue_time]).to eq(0.1)
        expect(metrics[:processing_time]).to eq(1.8)
        expect(metrics[:retry_delay]).to eq(5.0)
      end

      it 'provides defaults for missing values' do
        empty_event = {}
        metrics = subscriber.send(:extract_performance_metrics, empty_event)

        expect(metrics[:memory_usage]).to eq(0)
        expect(metrics[:cpu_time]).to eq(0.0)
        expect(metrics[:queue_time]).to eq(0.0)
        expect(metrics[:processing_time]).to eq(0.0)
        expect(metrics[:retry_delay]).to eq(0.0)
      end
    end

    describe '#extract_metric_tags' do
      let(:tagged_event) do
        {
          task_name: 'order_process',
          step_name: 'process_payment',
          source_system: 'ecommerce',
          retryable: true,
          attempt_number: 2,
          priority: 'high'
        }
      end

      it 'generates appropriate tags' do
        tags = subscriber.send(:extract_metric_tags, tagged_event)

        expect(tags).to include('task:order_process')
        expect(tags).to include('step:process_payment')
        expect(tags).to include('source:ecommerce')
        expect(tags).to include('retryable:true')
        expect(tags).to include('attempt:2')
        expect(tags).to include('priority:high')
        expect(tags).to include("environment:#{Rails.env}")
      end

      it 'filters out unknown/empty values' do
        sparse_event = { task_name: 'unknown', step_name: nil, source_system: 'valid' }
        tags = subscriber.send(:extract_metric_tags, sparse_event)

        expect(tags).not_to include('task:unknown')
        expect(tags).not_to include('step:unknown_step')
        expect(tags).to include('source:valid')
      end
    end

    describe '#build_metric_name' do
      it 'builds consistent metric names' do
        expect(subscriber.send(:build_metric_name, 'tasker.task', 'completed'))
          .to eq('tasker.task.completed')

        expect(subscriber.send(:build_metric_name, 'custom', 'failed'))
          .to eq('custom.failed')
      end

      it 'handles multiple dots correctly' do
        expect(subscriber.send(:build_metric_name, 'app.tasker.task', 'retry'))
          .to eq('app.tasker.task.retry')
      end
    end

    describe '#extract_numeric_metric' do
      let(:numeric_event) do
        {
          duration: 45.5,
          count: '10',
          invalid: 'not_a_number',
          nil_value: nil
        }
      end

      it 'extracts numeric values safely' do
        expect(subscriber.send(:extract_numeric_metric, numeric_event, :duration, 0.0))
          .to eq(45.5)

        expect(subscriber.send(:extract_numeric_metric, numeric_event, :count, 0))
          .to eq(10.0)
      end

      it 'returns defaults for invalid values' do
        expect(subscriber.send(:extract_numeric_metric, numeric_event, :invalid, 99.9))
          .to eq(99.9)

        expect(subscriber.send(:extract_numeric_metric, numeric_event, :nil_value, 42.0))
          .to eq(42.0)

        expect(subscriber.send(:extract_numeric_metric, numeric_event, :missing, 123.0))
          .to eq(123.0)
      end
    end

    describe '#categorize_error (private method)' do
      it 'categorizes various error types correctly' do
        categorization_tests = [
          ['Net::TimeoutError', 'timeout'],
          ['TimeoutError', 'timeout'],
          ['ConnectionError', 'network'],
          ['NetworkError', 'network'],
          ['ActiveRecord::RecordNotFound', 'not_found'],
          ['NotFoundError', 'not_found'],
          ['UnauthorizedError', 'auth'],
          ['ForbiddenError', 'auth'],
          ['RateLimitError', 'rate_limit'],
          ['TooManyRequestsError', 'rate_limit'],
          ['BadRequestError', 'client_error'],
          ['InvalidError', 'client_error'],
          ['InternalServerError', 'server_error'],
          ['ServerError', 'server_error'],
          ['StandardError', 'runtime'],
          ['RuntimeError', 'runtime'],
          ['CustomWeirdError', 'other'],
          [nil, 'unknown'],
          ['', 'unknown']
        ]

        categorization_tests.each do |error_class, expected_category|
          result = subscriber.send(:categorize_error, error_class)
          expect(result).to eq(expected_category),
                            "Expected #{error_class.inspect} to be categorized as '#{expected_category}', got '#{result}'"
        end
      end
    end
  end
end
