# frozen_string_literal: true

module Tasker
  module Events
    # Event Catalog provides discovery and documentation for all Tasker events
    #
    # This class enables developers to explore and understand the event system
    # with runtime introspection, payload schemas, and usage examples.
    #
    # All metadata is now sourced from Constants::EventDefinitions to ensure
    # a single source of truth between registration and documentation.
    #
    # Usage:
    #   # Browse all available events
    #   Tasker::Events.catalog
    #
    #   # Get details about a specific event
    #   Tasker::Events.event_info('task.completed')
    #
    #   # List events by category
    #   Tasker::Events.task_events
    #   Tasker::Events.step_events
    class Catalog
      class << self
        # Get complete event catalog with descriptions and schemas
        # Now reads directly from EventDefinitions for consistency
        #
        # @return [Hash] Complete event catalog
        def catalog
          @catalog ||= build_catalog_from_definitions
        end

        # Get information about a specific event
        #
        # @param event_name [String, Symbol] The event name
        # @return [Hash, nil] Event information or nil if not found
        def event_info(event_name)
          definition = Tasker::Constants::EventDefinitions.find_by_constant(event_name.to_s)
          return nil unless definition

          format_event_info(definition)
        end

        # Get all task-related events
        #
        # @return [Hash] Task events with documentation
        def task_events
          catalog.select { |_, event| event[:category] == 'task' }
        end

        # Get all step-related events
        #
        # @return [Hash] Step events with documentation
        def step_events
          catalog.select { |_, event| event[:category] == 'step' }
        end

        # Get all workflow orchestration events
        #
        # @return [Hash] Workflow events with documentation
        def workflow_events
          catalog.select { |_, event| event[:category] == 'workflow' }
        end

        # Get all observability events
        #
        # @return [Hash] Observability events with documentation
        def observability_events
          catalog.select { |_, event| event[:category] == 'observability' }
        end

        # List all registered custom events
        #
        # @return [Array<String>] Custom event names
        def custom_events
          # This would be populated by BaseSubscriber registrations
          @custom_events ||= []
        end

        # Register a custom event (called by BaseSubscriber)
        #
        # @param event_name [String] The custom event name
        # @param metadata [Hash] Optional metadata about the event
        # @return [void]
        def register_custom_event(event_name, metadata = {})
          @custom_events ||= []
          @custom_events << event_name unless @custom_events.include?(event_name)

          # Add to catalog if metadata provided
          if metadata.any?
            @catalog ||= {}
            @catalog[event_name] = {
              name: event_name,
              category: 'custom',
              description: metadata[:description] || 'Custom event',
              payload_schema: metadata[:payload_schema] || {},
              example_payload: metadata[:example] || {},
              fired_by: metadata[:fired_by] || ['Custom']
            }
          end
        end

        # Pretty print the catalog for console exploration
        #
        # @return [void]
        def print_catalog
          puts "\n📊 Tasker Event Catalog"
          puts "=" * 50

          %w[task step workflow observability custom].each do |category|
            events = catalog.select { |_, event| event[:category] == category }
            next if events.empty?

            puts "\n🔹 #{category.capitalize} Events:"
            events.each do |_, event|
              puts "  #{event[:name]}"
              puts "    Description: #{event[:description]}"
              puts "    Fired by: #{event[:fired_by].join(', ')}"
              puts "    Payload: #{event[:payload_schema].keys.join(', ')}" if event[:payload_schema].any?
              puts
            end
          end
        end

        private

        # Build the complete event catalog from EventDefinitions
        # This ensures consistency between registration and documentation
        #
        # @return [Hash] Complete event catalog
        def build_catalog_from_definitions
          catalog = {}

          Tasker::Constants::EventDefinitions.all_events.each do |category, events|
            events.each do |key, event_definition|
              event_constant = event_definition[:constant]
              catalog[event_constant] = format_event_info(event_definition.merge(key: key))
            end
          end

          catalog
        end

        # Format event definition into catalog format
        #
        # @param definition [Hash] Event definition from EventDefinitions
        # @return [Hash] Formatted event info
        def format_event_info(definition)
          {
            name: definition[:constant],
            category: definition[:category],
            description: definition[:description],
            payload_schema: definition[:payload_schema],
            example_payload: generate_example_payload(definition[:payload_schema]),
            fired_by: definition[:fired_by]
          }
        end

        # Generate example payload from schema
        #
        # @param schema [Hash] Payload schema
        # @return [Hash] Example payload
        def generate_example_payload(schema)
          example = {}
          schema.each do |key, type|
            example[key] = case type
                          when 'String'
                            key.to_s.include?('id') ? "#{key}_123" : "example_#{key}"
                          when 'Integer'
                            key.to_s.include?('count') ? 5 : 1
                          when 'Float'
                            2.34
                          when 'Time'
                            Time.current
                          when 'Array<String>'
                            ["item1", "item2"]
                          else
                            "example_#{key}"
                          end
          end
          example
        end
      end
    end

    # Convenience methods for the module
    class << self
      delegate :catalog, :event_info, :task_events, :step_events, :workflow_events,
               :observability_events, :custom_events, :print_catalog, to: :catalog_instance

      private

      def catalog_instance
        @catalog_instance ||= Catalog
      end
    end
  end
end
