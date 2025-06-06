# frozen_string_literal: true

require 'yaml'

module Tasker
  module Constants
    # EventDefinitions provides a bridge between event constants and their metadata
    #
    # This class loads event metadata from system_events.yml and provides methods
    # to find events by constant, retrieve all events by category, etc.
    # It serves as the single source of truth for event documentation and payload schemas.
    class EventDefinitions
      class << self
        # Find event definition by constant name
        #
        # @param constant [String] The event constant (e.g., 'task.completed')
        # @return [Hash, nil] Event definition or nil if not found
        def find_by(constant:)
          event_metadata.find { |_key, data| data['constant'] == constant }&.last
        end

        # Get all events grouped by category
        #
        # @return [Hash] Events grouped by category (task, step, workflow, etc.)
        def all_events
          @all_events ||= build_all_events
        end

        # Get events for a specific category
        #
        # @param category [String] The event category (task, step, workflow, etc.)
        # @return [Hash] Events in the specified category
        def events_by_category(category)
          all_events[category.to_s] || {}
        end

        # Get all event constants
        #
        # @return [Array<String>] All event constant names
        def all_constants
          event_metadata.values.pluck('constant').compact
        end

        # Refresh cached data (useful for testing)
        #
        # @return [void]
        def refresh!
          @event_metadata = nil
          @all_events = nil
        end

        private

        # Load and cache event metadata from system_events.yml
        #
        # @return [Hash] Event metadata with descriptions and schemas
        def event_metadata
          @event_metadata ||= load_event_metadata
        end

        # Load event metadata from YAML configuration
        #
        # @return [Hash] Parsed event metadata
        def load_event_metadata
          yaml_file = File.join(Tasker::Engine.root, 'config', 'tasker', 'system_events.yml')

          unless File.exist?(yaml_file)
            Rails.logger.warn("EventDefinitions: system_events.yml not found at #{yaml_file}")
            return {}
          end

          yaml_data = YAML.load_file(yaml_file)
          events_data = yaml_data['event_metadata'] || {}

          # Flatten nested events structure
          flattened = {}
          events_data.each do |category, category_events|
            category_events.each do |event_key, event_data|
              # Generate the full key for this event
              full_key = "#{category}_#{event_key}"

              # Get the constant reference and resolve it to actual constant value
              constant_ref = event_data['constant_ref']
              constant_value = resolve_constant_reference(constant_ref)

              if constant_value
                # Enhance event data with resolved constant and category
                enhanced_data = event_data.merge(
                  'constant' => constant_value,
                  'category' => category,
                  'key' => event_key
                )
                flattened[full_key] = enhanced_data
              else
                Rails.logger.warn("EventDefinitions: Could not resolve constant #{constant_ref}")
              end
            end
          end

          flattened
        rescue StandardError => e
          Rails.logger.error("EventDefinitions: Failed to load event metadata: #{e.message}")
          {}
        end

        # Resolve constant reference to actual constant value
        #
        # @param constant_ref [String] The constant reference (e.g., "Tasker::Constants::TaskEvents::COMPLETED")
        # @return [String, nil] The constant value or nil if not found
        def resolve_constant_reference(constant_ref)
          return nil unless constant_ref

          # Split the constant reference and navigate to it
          # E.g., "Tasker::Constants::TaskEvents::COMPLETED" -> ["Tasker", "Constants", "TaskEvents", "COMPLETED"]
          parts = constant_ref.split('::')

          # Start with the root constant (Tasker)
          current = Object.const_get(parts.first)

          # Navigate through the nested constants
          parts[1..].each do |part|
            current = current.const_get(part)
          end

          current
        rescue NameError => e
          Rails.logger.debug { "EventDefinitions: Cannot resolve constant #{constant_ref}: #{e.message}" }
          nil
        end

        # Build all events grouped by category
        #
        # @return [Hash] Events grouped by category
        def build_all_events
          grouped = Hash.new { |h, k| h[k] = {} }

          event_metadata.each do |event_key, event_data|
            category = event_data['category']
            grouped[category][event_key] = event_data
          end

          grouped
        end
      end
    end
  end
end
