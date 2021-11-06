# typed: false
# frozen_string_literal: true

require 'json-schema'

module Tasker
  module TaskHandler
    def self.included(klass)
      klass.extend(ClassMethods)
      klass.include(InstanceMethods)
    end
  end
end
