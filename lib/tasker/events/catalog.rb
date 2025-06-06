# frozen_string_literal: true

require_relative 'custom_registry'

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
          definition = Tasker::Constants::EventDefinitions.find_by(constant: event_name.to_s)
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

        # Get complete catalog including custom events
        #
        # @return [Hash] All events (system + custom)
        def complete_catalog
          system_catalog = catalog
          custom_events_data = Tasker::Events::CustomRegistry.instance.custom_events

          # Format custom events to match system catalog structure
          formatted_custom = custom_events_data.transform_values do |event|
            {
              name: event[:name],
              category: event[:category],
              description: event[:description],
              fired_by: event[:fired_by],
              payload_schema: {}, # MVP: no schema validation yet
              example_payload: {} # MVP: no examples yet
            }
          end

          system_catalog.merge(formatted_custom)
        end

        # Get only custom events
        #
        # @return [Hash] Custom events with metadata
        def custom_events
          complete_catalog.select { |_, event| event[:category] == 'custom' }
        end

        # Search events by name or description
        #
        # @param query [String] Search query
        # @return [Hash] Matching events
        def search_events(query)
          complete_catalog.select do |name, event|
            name.downcase.include?(query.downcase) ||
              event[:description].downcase.include?(query.downcase)
          end
        end

        # Get events by namespace (e.g., 'order', 'payment')
        #
        # @param namespace [String] Event namespace
        # @return [Hash] Events in namespace
        def events_by_namespace(namespace)
          complete_catalog.select { |name, _| name.start_with?("#{namespace}.") }
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
          return unless metadata.any?

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

        # Pretty print the catalog for console exploration
        #
        # @param output [IO] Output destination (defaults to $stdout in development/test, Rails.logger in production)
        # @return [void]
        def print_catalog(output: nil)
          # Default to stdout in development/test for interactive exploration, logger in production
          output ||= (Rails.env.production? ? Rails.logger : $stdout)

          log_line = lambda do |message|
            if output == Rails.logger
              Rails.logger.debug message
            else
              output.puts message
            end
          end

          log_line.call "\n📊 Tasker Event Catalog"
          log_line.call '=' * 50

          %w[task step workflow observability custom].each do |category|
            # Use complete_catalog to include custom events
            events = complete_catalog.select { |_, event| event[:category] == category }
            next if events.empty?

            log_line.call "\n🔹 #{category.capitalize} Events:"
            events.each_value do |event|
              log_line.call "  #{event[:name]}"
              log_line.call "    Description: #{event[:description]}"
              log_line.call "    Fired by: #{event[:fired_by].join(', ')}"
              log_line.call "    Payload: #{event[:payload_schema].keys.join(', ')}" if event[:payload_schema].any?
              log_line.call ''
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

          Tasker::Constants::EventDefinitions.all_events.each_value do |events|
            events.each_value do |event_definition|
              event_constant = event_definition['constant'] || event_definition[:constant]
              next unless event_constant

              catalog[event_constant] = format_event_info(event_definition)
            end
          end

          catalog
        end

        # Format event definition into catalog format
        #
        # @param definition [Hash] Event definition from EventDefinitions
        # @return [Hash] Formatted event info
        def format_event_info(definition)
          # Handle both symbol and string keys for flexibility
          constant = definition[:constant] || definition['constant']
          category = definition[:category] || definition['category']
          description = definition[:description] || definition['description']
          payload_schema = definition[:payload_schema] || definition['payload_schema']
          fired_by = definition[:fired_by] || definition['fired_by'] || []

          {
            name: constant,
            category: category,
            description: description,
            payload_schema: payload_schema,
            example_payload: generate_example_payload(payload_schema),
            fired_by: fired_by
          }
        end

        # Generate example payload from schema
        #
        # @param schema [Hash] Payload schema
        # @return [Hash] Example payload
        def generate_example_payload(schema)
          return {} if schema.blank?

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
                             %w[item1 item2]
                           else
                             "example_#{key}"
                           end
          end
          example
        end
      end
    end
  end
end

# Delegation is handled in lib/tasker/events.rb
