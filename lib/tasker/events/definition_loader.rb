# frozen_string_literal: true

require 'yaml'

module Tasker
  module Events
    # DefinitionLoader handles loading event metadata and state machine mappings from YAML files
    #
    # This class provides a clean loader for event metadata (descriptions, schemas, etc.)
    # and state machine transition mappings. The actual event constants are defined
    # in constants.rb as the single source of truth.
    #
    # Features:
    # - Event metadata loading for runtime introspection
    # - State machine transition mappings for declarative configuration
    # - Support for custom application events and mappings
    # - Hot reloading in development environments
    class DefinitionLoader
      include Singleton

      class << self
        # Load all event metadata for introspection
        #
        # @return [Hash] Event metadata keyed by constant reference
        def load_event_metadata
          metadata = {}

          # Load system event metadata first
          system_metadata = load_system_event_metadata
          metadata.merge!(system_metadata)

          # Load custom event metadata from applications
          custom_metadata = load_custom_event_metadata
          metadata.merge!(custom_metadata)

          metadata
        end

        # Load state machine mappings from YAML
        #
        # @return [Hash] State machine mappings with task and step transitions
        def load_state_machine_mappings
          yaml_file = File.join(tasker_config_path, 'system_events.yml')

          if File.exist?(yaml_file)
            yaml_data = YAML.load_file(yaml_file)
            yaml_data['state_machine_mappings'] || {}
          else
            Rails.logger.warn('Tasker: system_events.yml not found')
            {}
          end
        end

        # Get event metadata for a specific constant
        #
        # @param constant_ref [String] The constant reference or actual constant value
        # @return [Hash, nil] Event metadata or nil if not found
        def find_event_metadata(constant_ref)
          metadata = load_event_metadata

          # Try direct lookup first
          return metadata[constant_ref] if metadata[constant_ref]

          # Try reverse lookup by constant value
          metadata.find { |_key, data| data['constant_ref'] == constant_ref }&.last
        end

        # Get all events grouped by category for introspection
        #
        # @return [Hash] Events grouped by category (task, step, workflow, etc.)
        def events_by_category
          metadata = load_event_metadata
          grouped = Hash.new { |h, k| h[k] = {} }

          metadata.each do |event_key, event_data|
            category = extract_category_from_key(event_key)
            grouped[category][event_key] = event_data
          end

          grouped
        end

        private

        # Load system event metadata from Tasker gem
        #
        # @return [Hash] System event metadata
        def load_system_event_metadata
          system_file = File.join(tasker_config_path, 'system_events.yml')

          if File.exist?(system_file)
            load_metadata_from_file(system_file)
          else
            Rails.logger.warn("Tasker: System events file not found at #{system_file}")
            {}
          end
        end

        # Load custom event metadata from application configuration
        #
        # @return [Hash] Custom event metadata
        def load_custom_event_metadata
          metadata = {}

          # Load custom events from configured directories if they exist
          Tasker::Configuration.configuration.engine.custom_events_directories.each do |directory_path|
            absolute_path = File.expand_path(directory_path, Rails.root)

            if File.directory?(absolute_path)
              load_metadata_from_directory(absolute_path, metadata)
            elsif File.exist?(absolute_path) && absolute_path.end_with?('.yml', '.yaml')
              file_metadata = load_metadata_from_file(absolute_path)
              metadata.merge!(file_metadata)
            end
          end

          metadata
        end

        # Load metadata from a single YAML file
        #
        # @param file_path [String] Path to the YAML file
        # @return [Hash] Event metadata from the file
        def load_metadata_from_file(file_path)
          Rails.logger.debug { "Tasker: Loading event metadata from #{file_path}" }

          begin
            yaml_data = YAML.load_file(file_path)
            return {} if yaml_data.blank?

            # Extract event metadata section
            event_metadata = yaml_data['event_metadata'] || {}
            transform_metadata_structure(event_metadata, file_path)
          rescue StandardError => e
            Rails.logger.error("Tasker: Failed to load event metadata from #{file_path}: #{e.message}")
            {}
          end
        end

        # Transform nested YAML metadata structure to flat lookup
        #
        # @param metadata [Hash] Nested metadata structure from YAML
        # @param source_file [String] Source file for metadata attribution
        # @return [Hash] Flattened metadata hash
        def transform_metadata_structure(metadata, source_file)
          flattened = {}

          metadata.each do |category, events|
            events.each do |event_name, event_data|
              # Create a composite key for easy lookup
              lookup_key = "#{category}.#{event_name}"

              # Enhance event data with source information
              enhanced_data = event_data.merge(
                'category' => category.to_s,
                'event_name' => event_name.to_s,
                'source_file' => source_file,
                'lookup_key' => lookup_key
              )

              flattened[lookup_key] = enhanced_data
            end
          end

          flattened
        end

        # Extract category from composite event key
        #
        # @param event_key [String] The composite event key (e.g., "task.completed")
        # @return [String] The category portion
        def extract_category_from_key(event_key)
          event_key.split('.').first || 'unknown'
        end

        # Load metadata from a directory
        #
        # @param directory_path [String] Absolute path to the directory
        # @param metadata [Hash] Hash to merge metadata into
        # @return [void]
        def load_metadata_from_directory(directory_path, metadata)
          Rails.logger.debug { "Tasker: Scanning directory for metadata files: #{directory_path}" }

          Dir.glob(File.join(directory_path, '*.{yml,yaml}')).each do |metadata_file|
            file_metadata = load_metadata_from_file(metadata_file)
            metadata.merge!(file_metadata)
          end
        end

        # Get path to Tasker gem configuration
        #
        # @return [String] Path to Tasker config directory
        def tasker_config_path
          @tasker_config_path ||= File.join(Tasker::Engine.root, 'config', 'tasker')
        end
      end
    end
  end
end
