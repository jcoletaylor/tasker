# frozen_string_literal: true

require 'rails/generators'

module Tasker
  module Generators
    class SubscriberGenerator < Rails::Generators::NamedBase
      source_root File.expand_path('templates', __dir__)

      desc 'Generate a new Tasker event subscriber'

      class_option :events, type: :array, default: [],
                            desc: 'Events to subscribe to (e.g., task.completed step.failed)'

      class_option :directory, type: :string, default: 'app/subscribers',
                               desc: 'Directory to place the subscriber'

      def create_subscriber_file
        template 'subscriber.rb.erb', File.join(options[:directory], "#{file_name}_subscriber.rb")
      end

      def create_spec_file
        return unless defined?(RSpec)

        template 'subscriber_spec.rb.erb', File.join('spec', 'subscribers', "#{file_name}_subscriber_spec.rb")
      end

      def show_usage_instructions
        say "\n#{set_color('Subscriber created successfully!', :green)}"
        say "\nTo register your subscriber, add this to an initializer:"
        say set_color("  #{class_name}Subscriber.subscribe(Tasker::Events::Publisher.instance)", :cyan)

        if options[:events].any?
          say "\nYour subscriber will handle these events:"
          options[:events].each do |event|
            method_name = "handle_#{event.tr('.', '_')}"
            say set_color("  #{event} -> #{method_name}", :yellow)
          end
        end

        say "\nAvailable events can be viewed with:"
        say set_color('  Tasker::Events.catalog.keys', :cyan)
      end

      private

      def file_name
        @file_name ||= name.underscore
      end

      def class_name
        @class_name ||= name.camelize
      end

      def subscribed_events
        options[:events]
      end

      def handler_methods
        options[:events].map do |event|
          {
            event: event,
            method_name: "handle_#{event.tr('.', '_')}",
            method_signature: "handle_#{event.tr('.', '_')}(event)"
          }
        end
      end
    end
  end
end
