# frozen_string_literal: true

require 'rails/generators'

module Tasker
  class EventsGenerator < Rails::Generators::Base
    source_root File.expand_path('templates', __dir__)

    desc 'Set up Tasker custom events configuration'

    class_option :create_example, type: :boolean, default: true,
                                  desc: 'Create example custom events file'

    def create_config_directory
      empty_directory 'config/tasker'
      empty_directory 'config/tasker/events'
    end

    def create_events_config
      if options[:create_example]
        template 'custom_events.yml.erb', 'config/tasker/events/examples.yml'
        say 'Created config/tasker/events/examples.yml with example custom events', :green
      else
        create_file 'config/tasker/events/.keep', ''
        say 'Created config/tasker/events/ directory (add your event YAML files here)', :green
      end
    end

    def create_example_subscriber
      return unless options[:create_example]

      template 'custom_subscriber.rb.erb', 'app/subscribers/custom_events_subscriber.rb'
      say 'Created app/subscribers/custom_events_subscriber.rb', :green
    end

    def display_setup_instructions
      say <<~INSTRUCTIONS, :blue

        🎉 Tasker Events Setup Complete!

        📂 Default Event Location:
        Your custom events are loaded from: config/tasker/events/*.yml

        Next steps:
        1. Add more event files to config/tasker/events/ as needed
        2. Create subscribers in app/subscribers/ to handle events
        3. Use EventPublisher concern to publish custom events

        💡 Simple Organization:
        config/
          tasker/
            events/
              orders.yml       # order.created, order.cancelled
              payments.yml     # payment.attempted, payment.completed
              notifications.yml # notification.sent, notification.failed

        🔧 Advanced Configuration (if needed):
        For complex organizational needs, configure additional directories:

          Tasker.configuration do |config|
            config.add_custom_events_directories(
              'vendor/gems/my_gem/events',
              'app/modules/billing/events'
            )
          end

        Example subscriber:
          class OrderEventsSubscriber < Tasker::Events::Subscribers::BaseSubscriber
            subscribe_to 'order.processed'

            def handle_order_processed(event)
              # Handle the event
            end
          end

        Example publishing:
          include Tasker::Concerns::EventPublisher
          publish_event('order.processed', { order_id: '123' })

        For more information, see the Tasker documentation.

      INSTRUCTIONS
    end

    private

    def application_name
      Rails.application.class.module_parent_name.underscore
    end
  end
end
