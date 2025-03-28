# frozen_string_literal: true

class EventBus
  class << self
    def publish(event_name, payload)
      # In a real implementation, this would publish to SQS, ActiveMQ, etc.
      {
        event_name: event_name,
        payload: payload,
        published_at: Time.zone.now,
        published_to: 'SQS',
        published_to_id: '1234567890',
        message_id: SecureRandom.uuid,
        published_status: 'success',
        published_status_message: 'Event published successfully',
        status: 'placed_pending_fulfillment'
      }
    end

    def subscribe(event_name, &)
      # In a real implementation, this would subscribe to a queue, ActiveMQ, etc.
      {
        event_name: event_name,
        subscribed_at: Time.zone.now,
        subscribed_to: 'SQS',
        subscribed_to_id: '1234567890',
        message_id: SecureRandom.uuid,
        subscribed_status: 'success',
        subscribed_status_message: 'Event subscribed successfully'
      }
    end
  end
end
