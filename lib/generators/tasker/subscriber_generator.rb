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

      class_option :metrics, type: :boolean, default: false,
                             desc: 'Generate a specialized metrics collection subscriber'

      def create_subscriber_file
        if options[:metrics]
          template 'metrics_subscriber.rb.erb', File.join(options[:directory], "#{file_name}_subscriber.rb")
        else
          template 'subscriber.rb.erb', File.join(options[:directory], "#{file_name}_subscriber.rb")
        end
      end

      def create_spec_file
        return unless defined?(RSpec)

        if options[:metrics]
          template 'metrics_subscriber_spec.rb.erb', File.join('spec', 'subscribers', "#{file_name}_subscriber_spec.rb")
        else
          template 'subscriber_spec.rb.erb', File.join('spec', 'subscribers', "#{file_name}_subscriber_spec.rb")
        end
      end

      def show_usage_instructions
        say "\n#{set_color('Subscriber created successfully!', :green)}"

        if options[:metrics]
          say "\n#{set_color('Metrics subscriber features:', :cyan)}"
          say '  - Built-in helper methods for extracting timing, error, and performance metrics'
          say '  - Automatic tag generation for categorization'
          say '  - Examples for StatsD, DataDog, Prometheus, and other metrics systems'
          say '  - Safe numeric value extraction with defaults'
        end

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

        return unless options[:metrics]

        say "\n#{set_color('Metrics collection examples:', :green)}"
        say '  - Task completion rates and durations'
        say '  - Error categorization and retry patterns'
        say '  - Performance monitoring and resource usage'
        say '  - Business metrics with proper tagging'
      end

      private

      def file_name
        @file_name ||= name.underscore
      end

      def class_name
        @class_name ||= name.camelize
      end

      def subscribed_events
        if options[:metrics] && options[:events].empty?
          # Default to common metrics events if none specified
          %w[task.completed task.failed step.completed step.failed]
        else
          options[:events]
        end
      end

      def handler_methods
        subscribed_events.map do |event|
          {
            event: event,
            method_name: "handle_#{event.tr('.', '_')}",
            method_signature: "handle_#{event.tr('.', '_')}(event)"
          }
        end
      end

      def metrics_type?
        options[:metrics]
      end
    end
  end
end
