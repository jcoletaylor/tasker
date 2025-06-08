# frozen_string_literal: true

module Tasker
  # Base error class for all Tasker-related errors
  class Error < StandardError; end

  # Raised when there are configuration-related issues in Tasker
  class ConfigurationError < Error; end
end
