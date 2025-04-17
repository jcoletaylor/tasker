# frozen_string_literal: true

# typed: false

module Tasker
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end
end
