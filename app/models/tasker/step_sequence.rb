# typed: true
# frozen_string_literal: true

module Tasker
  StepSequence =
    Struct.new(:steps) do
      def initialize(options)
        options.each do |key, value|
          __send__(:"#{key}=", value) if value.present?
        end
        self.steps ||= []
      end
    end
end
