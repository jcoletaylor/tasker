# typed: false
# frozen_string_literal: true

# Registry module for Tasker
#
# Provides unified registry management with thread-safe operations,
# validation, observability, and coordination capabilities.
module Tasker
  module Registry
    # Registry-related errors
    class RegistryError < StandardError; end
    class ValidationError < RegistryError; end
    class RegistrationError < RegistryError; end
  end
end

# Require all registry components
require_relative 'registry/base_registry'
require_relative 'registry/interface_validator'
require_relative 'registry/event_publisher'
require_relative 'registry/subscriber_registry'
require_relative 'registry/statistics_collector'
