# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Concerns::EventPublisher do
  # Create a test class that includes the concern
  let(:test_class) do
    Class.new do
      include Tasker::Concerns::EventPublisher
    end
  end

  let(:publisher) { test_class.new }
  let(:registry) { Tasker::Events::CustomRegistry.instance }
  let(:events_publisher) { Tasker::Events::Publisher.instance }

  before do
    # Clear registry between tests
    registry.clear!

    # Mock the actual events publisher that gets called
    allow(events_publisher).to receive(:publish)
  end

  describe '#publish_custom_event' do
    it 'publishes a custom event with enhanced payload' do
      freeze_time = Time.current
      allow(Time).to receive(:current).and_return(freeze_time)

      expect(events_publisher).to receive(:publish).with(
        'order.fulfilled',
        hash_including(
          event_type: 'custom',
          timestamp: freeze_time,
          order_id: '12345'
        )
      )

      publisher.publish_custom_event('order.fulfilled', order_id: '12345')
    end

    it 'merges custom payload with standard metadata' do
      custom_payload = { order_id: '12345', amount: 99.99 }

      expect(events_publisher).to receive(:publish) do |event_name, payload|
        expect(event_name).to eq('payment.processed')
        expect(payload).to include(custom_payload)
        expect(payload[:event_type]).to eq('custom')
        expect(payload[:timestamp]).to be_present
      end

      publisher.publish_custom_event('payment.processed', custom_payload)
    end
  end

  describe 'integration with Events module' do
    it 'works with the Events.register_custom_event API' do
      Tasker::Events.register_custom_event(
        'customer.signup',
        description: 'New customer signed up',
        fired_by: ['UserService']
      )

      expect(events_publisher).to receive(:publish).with(
        'customer.signup',
        hash_including(
          event_type: 'custom',
          customer_id: 'CUST123'
        )
      )

      publisher.publish_custom_event('customer.signup', customer_id: 'CUST123')
    end
  end

  describe 'realistic usage scenario' do
    it 'demonstrates a complete workflow' do
      # Step 1: Register custom events (typically in initializer)
      Tasker::Events.register_custom_event(
        'order.risk_flagged',
        description: 'Order flagged for manual review due to risk factors',
        fired_by: %w[RiskAssessmentService FraudDetectionService]
      )

      # Step 2: Publish from business logic (step handler)
      expect(events_publisher).to receive(:publish).with(
        'order.risk_flagged',
        hash_including(
          event_type: 'custom',
          order_id: 'ORDER123',
          risk_score: 85,
          flagged_reasons: %w[high_value new_customer]
        )
      )

      publisher.publish_custom_event('order.risk_flagged', {
                                       order_id: 'ORDER123',
                                       risk_score: 85,
                                       flagged_reasons: %w[high_value new_customer],
                                       requires_manual_review: true
                                     })

      # Step 3: Verify event is discoverable
      expect(Tasker::Events.custom_events.keys).to include('order.risk_flagged')
      expect(Tasker::Events.search_events('risk')).to have_key('order.risk_flagged')
    end
  end
end
