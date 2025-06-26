# typed: false
# frozen_string_literal: true

# Base stub class for test task handlers
#
# This class properly implements the TaskHandler interface to satisfy
# validation requirements while providing sensible defaults for testing.
# Test task handlers should inherit from this class instead of implementing
# the interface from scratch.
class StubTaskHandler
  include Tasker::TaskHandler

  # Default schema for test validation
  # Override in subclasses as needed
  def schema
    {
      type: 'object',
      properties: {
        test_data: { type: 'string' }
      }
    }
  end

  # Optional annotation method (noop by default)
  # Override in subclasses if needed
  def update_annotations(_task, _sequence, _steps)
    # Noop implementation for testing
  end

  # Class method to make it easy to create test handlers
  def self.create_test_handler(name, options = {})
    Class.new(self) do
      @handler_name = name
      @handler_options = options

      # Override schema if provided
      if options[:schema]
        define_method :schema do
          options[:schema]
        end
      end

      # Set up step templates if provided
      if options[:step_templates]
        define_step_templates do |templates|
          options[:step_templates].each do |step_config|
            templates.define(step_config)
          end
        end
      end

      # Register the handler if name and registration options provided
      if name && options[:register]
        register_handler(
          name,
          namespace_name: options[:namespace] || :default,
          version: options[:version] || '0.1.0'
        )
      end

      # Allow access to configuration
      class << self
        attr_reader :handler_name
      end

      class << self
        attr_reader :handler_options
      end
    end
  end
end
