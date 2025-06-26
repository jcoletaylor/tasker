# typed: false
# frozen_string_literal: true

# Base stub class for test step handlers
#
# This class properly implements the StepHandler interface to satisfy
# validation requirements while providing sensible defaults for testing.
# Test step handlers should inherit from this class.
class StubStepHandler < Tasker::StepHandler::Base
  # Default process implementation that satisfies interface requirements
  # Override in subclasses as needed
  def process(_task, _sequence, _step)
    { status: 'completed', processed_at: Time.current }
  end

  # Class method version for handlers that use class-level processing
  def self.process(_task, _sequence, _step)
    { status: 'completed', processed_at: Time.current }
  end

  # Class method to make it easy to create test step handlers
  def self.create_test_step_handler(name = nil, options = {})
    Class.new(self) do
      @handler_name = name
      @handler_options = options

      # Allow custom process implementation
      if options[:process_implementation]
        define_method :process do |task, sequence, step|
          options[:process_implementation].call(task, sequence, step)
        end
      end

      # Allow custom class-level process implementation
      if options[:class_process_implementation]
        define_singleton_method :process do |task, sequence, step|
          options[:class_process_implementation].call(task, sequence, step)
        end
      end

      # Custom event configuration if provided
      if options[:custom_events]
        define_singleton_method :custom_event_configuration do
          options[:custom_events]
        end
      end

      class << self
        attr_reader :handler_name
      end

      class << self
        attr_reader :handler_options
      end
    end
  end
end
