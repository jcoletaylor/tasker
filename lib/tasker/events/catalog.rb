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
          CustomEventRegistrar.register(event_name, metadata, self)
        end

        # Pretty print the catalog for console exploration
        #
        # @param output [IO] Output destination (defaults to $stdout in development/test, Rails.logger in production)
        # @return [void]
        def print_catalog(output: nil)
          CatalogPrinter.print(complete_catalog, output)
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
            example[key] = ExamplePayloadGenerator.generate_value(key, type)
          end
          example
        end

        # Service class to generate example values for different data types
        # Reduces complexity by organizing type-specific generation logic
        class ExamplePayloadGenerator
          class << self
            # Generate example value for a key-type pair
            #
            # @param key [String, Symbol] The key name
            # @param type [String] The data type
            # @return [Object] Generated example value
            def generate_value(key, type)
              case type
              when 'String'
                generate_string_value(key)
              when 'Integer'
                generate_integer_value(key)
              when 'Float'
                generate_float_value
              when 'Time'
                generate_time_value
              when 'Array<String>'
                generate_string_array_value
              else
                generate_default_value(key)
              end
            end

            private

            # Generate example string value based on key name
            #
            # @param key [String, Symbol] The key name
            # @return [String] Generated string value
            def generate_string_value(key)
              key.to_s.include?('id') ? "#{key}_123" : "example_#{key}"
            end

            # Generate example integer value based on key name
            #
            # @param key [String, Symbol] The key name
            # @return [Integer] Generated integer value
            def generate_integer_value(key)
              key.to_s.include?('count') ? 5 : 1
            end

            # Generate example float value
            #
            # @return [Float] Generated float value
            def generate_float_value
              2.34
            end

            # Generate example time value
            #
            # @return [Time] Current time
            def generate_time_value
              Time.current
            end

            # Generate example string array value
            #
            # @return [Array<String>] Generated array of strings
            def generate_string_array_value
              %w[item1 item2]
            end

            # Generate default example value
            #
            # @param key [String, Symbol] The key name
            # @return [String] Default example value
            def generate_default_value(key)
              "example_#{key}"
            end
          end
        end

        # Service class to handle custom event registration
        # Reduces complexity by organizing registration logic
        class CustomEventRegistrar
          class << self
            # Register a custom event with metadata
            #
            # @param event_name [String] The custom event name
            # @param metadata [Hash] Optional metadata about the event
            # @param catalog_instance [Catalog] The catalog instance to update
            # @return [void]
            def register(event_name, metadata, catalog_instance)
              register_event_name(event_name, catalog_instance)

              # Add to catalog if metadata provided
              return unless metadata.any?

              register_event_metadata(event_name, metadata, catalog_instance)
            end

            private

            # Register the event name in the custom events list
            #
            # @param event_name [String] The custom event name
            # @param catalog_instance [Catalog] The catalog instance to update
            # @return [void]
            def register_event_name(event_name, catalog_instance)
              unless catalog_instance.instance_variable_get(:@custom_events)
                catalog_instance.instance_variable_set(:@custom_events,
                                                       [])
              end
              custom_events = catalog_instance.instance_variable_get(:@custom_events)
              custom_events << event_name unless custom_events.include?(event_name)
            end

            # Register event metadata in the catalog
            #
            # @param event_name [String] The custom event name
            # @param metadata [Hash] Event metadata
            # @param catalog_instance [Catalog] The catalog instance to update
            # @return [void]
            def register_event_metadata(event_name, metadata, catalog_instance)
              unless catalog_instance.instance_variable_get(:@catalog)
                catalog_instance.instance_variable_set(:@catalog,
                                                       {})
              end
              catalog = catalog_instance.instance_variable_get(:@catalog)

              catalog[event_name] = build_catalog_entry(event_name, metadata)
            end

            # Build catalog entry from metadata
            #
            # @param event_name [String] The custom event name
            # @param metadata [Hash] Event metadata
            # @return [Hash] Catalog entry
            def build_catalog_entry(event_name, metadata)
              {
                name: event_name,
                category: 'custom',
                description: metadata[:description] || 'Custom event',
                payload_schema: metadata[:payload_schema] || {},
                example_payload: metadata[:example] || {},
                fired_by: metadata[:fired_by] || ['Custom']
              }
            end
          end
        end

        # Service class to handle catalog printing and formatting
        # Reduces complexity by organizing output logic
        class CatalogPrinter
          class << self
            # Print the complete catalog with formatting
            #
            # @param catalog [Hash] The complete catalog to print
            # @param output [IO] Output destination
            # @return [void]
            def print(catalog, output = nil)
              log_line = build_log_function(output)

              print_header(log_line)
              print_categories(catalog, log_line)
            end

            private

            # Build the appropriate logging function based on output type
            #
            # @param output [IO] Output destination
            # @return [Proc] Logging function
            def build_log_function(output)
              # Default to stdout in development/test for interactive exploration, logger in production
              output ||= (Rails.env.production? ? Rails.logger : $stdout)

              lambda do |message|
                if output == Rails.logger
                  Rails.logger.debug message
                else
                  output.puts message
                end
              end
            end

            # Print catalog header
            #
            # @param log_line [Proc] Logging function
            # @return [void]
            def print_header(log_line)
              log_line.call "\n📊 Tasker Event Catalog"
              log_line.call '=' * 50
            end

            # Print events organized by categories
            #
            # @param catalog [Hash] The complete catalog
            # @param log_line [Proc] Logging function
            # @return [void]
            def print_categories(catalog, log_line)
              %w[task step workflow observability custom].each do |category|
                events = catalog.select { |_, event| event[:category] == category }
                next if events.empty?

                print_category_events(category, events, log_line)
              end
            end

            # Print events for a specific category
            #
            # @param category [String] The category name
            # @param events [Hash] Events in the category
            # @param log_line [Proc] Logging function
            # @return [void]
            def print_category_events(category, events, log_line)
              log_line.call "\n🔹 #{category.capitalize} Events:"
              events.each_value do |event|
                print_event_details(event, log_line)
              end
            end

            # Print details for a single event
            #
            # @param event [Hash] Event details
            # @param log_line [Proc] Logging function
            # @return [void]
            def print_event_details(event, log_line)
              log_line.call "  #{event[:name]}"
              log_line.call "    Description: #{event[:description]}"
              log_line.call "    Fired by: #{event[:fired_by].join(', ')}"

              log_line.call "    Payload: #{event[:payload_schema].keys.join(', ')}" if event[:payload_schema].any?

              log_line.call ''
            end
          end
        end
      end
    end
  end
end

# Delegation is handled in lib/tasker/events.rb
