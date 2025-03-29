# frozen_string_literal: true

module Tasker
  module StepHandler
    class Base
      def initialize(config: nil)
        @config = config
      end

      def handle(task, sequence, step)
        raise NotImplementedError, 'Subclasses must implement this method'
      end
    end
  end
end
