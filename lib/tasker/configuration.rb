# frozen_string_literal: true

module Tasker
  class Configuration
    attr_accessor :task_handler_directory, :task_config_directory

    def initialize
      @task_handler_directory = 'tasks'
      @task_config_directory = 'tasks'
    end
  end

  # Global configuration
  def self.configuration
    @configuration ||= Configuration.new

    # Yield if a block is given for backwards compatibility
    yield(@configuration) if block_given?

    @configuration
  end

  def self.reset_configuration!
    @configuration = Configuration.new
  end
end
