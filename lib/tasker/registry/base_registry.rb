# typed: false
# frozen_string_literal: true

require_relative '../concerns/structured_logging'
require 'concurrent-ruby'

module Tasker
  module Registry
    # Base class for all registry systems in Tasker
    #
    # Provides common functionality including thread-safe operations,
    # structured logging, health checks, and statistics interfaces.
    # All registry classes should inherit from this base class.
    class BaseRegistry
      include Tasker::Concerns::StructuredLogging

      def initialize
        @mutex = Mutex.new
        @telemetry_config = Tasker::Configuration.configuration.telemetry
        @registry_name = self.class.name.demodulize.underscore
        @created_at = Time.current
      end

      protected

      # Log registration events with structured format
      #
      # @param entity_type [String] Type of entity being registered
      # @param entity_id [String] Unique identifier for the entity
      # @param entity_class [Class, String] Class of the entity being registered
      # @param options [Hash] Additional registration options
      def log_registration(entity_type, entity_id, entity_class, options = {})
        class_name = entity_class.is_a?(Class) ? entity_class.name : entity_class.to_s
        log_structured(:info, 'Registry item registered',
                       entity_type: entity_type,
                       entity_id: entity_id,
                       entity_class: class_name,
                       registry_name: @registry_name,
                       options: options,
                       event_type: :registered)
      end

      # Log unregistration events with structured format
      #
      # @param entity_type [String] Type of entity being unregistered
      # @param entity_id [String] Unique identifier for the entity
      # @param entity_class [Class, String] Class of the entity being unregistered
      def log_unregistration(entity_type, entity_id, entity_class)
        class_name = entity_class.is_a?(Class) ? entity_class.name : entity_class.to_s
        log_structured(:info, 'Registry item unregistered',
                       entity_type: entity_type,
                       entity_id: entity_id,
                       entity_class: class_name,
                       registry_name: @registry_name,
                       event_type: :unregistered)
      end

      # Log registry operations with structured format
      #
      # @param operation [String] Operation being performed
      # @param context [Hash] Additional context for the operation
      def log_registry_operation(operation, **context)
        log_structured(:debug, "Registry #{operation}",
                       registry_name: @registry_name,
                       operation: operation,
                       **context)
      end

      # Log registry errors with structured format
      #
      # @param operation [String] Operation that failed
      # @param error [Exception] The error that occurred
      # @param context [Hash] Additional context for the error
      def log_registry_error(operation, error, **context)
        log_structured(:error, "Registry #{operation} failed",
                       registry_name: @registry_name,
                       operation: operation,
                       error: error.message,
                       error_class: error.class.name,
                       **context)
      end

      # Log validation failures with structured format
      #
      # @param entity_type [String] Type of entity that failed validation
      # @param entity_id [String] Unique identifier for the entity
      # @param validation_error [String] Description of the validation failure
      def log_validation_failure(entity_type, entity_id, validation_error)
        log_structured(:error, 'Registry validation failed',
                       entity_type: entity_type,
                       entity_id: entity_id,
                       registry_name: @registry_name,
                       validation_error: validation_error,
                       event_type: :validation_failed)
      end

      # Validate registration parameters
      #
      # @param name [String] Name of the entity
      # @param entity_class [Class] Class of the entity
      # @param options [Hash] Registration options
      # @raise [ArgumentError] If parameters are invalid
      def validate_registration_params!(name, entity_class, options = {})
        raise ArgumentError, 'Name cannot be blank' if name.blank?
        raise ArgumentError, 'Entity class cannot be nil' if entity_class.nil?
        raise ArgumentError, 'Options must be a Hash' unless options.is_a?(Hash)
      end

      # Execute operations in a thread-safe manner
      #
      # @yield Block to execute within mutex
      # @return [Object] Result of the block
      def thread_safe_operation(&)
        @mutex.synchronize(&)
      end

      # Common registry statistics interface
      #
      # @return [Hash] Base statistics shared by all registries
      def base_stats
        {
          registry_name: @registry_name,
          created_at: @created_at,
          uptime_seconds: (Time.current - @created_at).to_i
        }
      end

      # Health check interface
      #
      # @return [Boolean] True if registry is healthy
      def healthy?
        # Basic health checks that all registries should pass
        !@mutex.locked? && respond_to?(:stats)
      end

      # Comprehensive health check with details
      #
      # @return [Hash] Health check results
      def health_check
        {
          healthy: healthy?,
          registry_name: @registry_name,
          stats: stats,
          last_check: Time.current
        }
      end

      public

      # Abstract methods that subclasses must implement

      # Get comprehensive statistics for this registry
      #
      # @return [Hash] Registry-specific statistics
      # @raise [NotImplementedError] Must be implemented by subclasses
      def stats
        raise NotImplementedError, 'Subclasses must implement #stats'
      end

      # Get all items in the registry
      #
      # @return [Hash] All registered items
      # @raise [NotImplementedError] Must be implemented by subclasses
      def all_items
        raise NotImplementedError, 'Subclasses must implement #all_items'
      end

      # Clear all items from the registry
      #
      # @return [void]
      # @raise [NotImplementedError] Must be implemented by subclasses
      def clear!
        raise NotImplementedError, 'Subclasses must implement #clear!'
      end
    end
  end
end
