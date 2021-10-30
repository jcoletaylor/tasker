# frozen_string_literal: true

# typed: strict
module Tasker
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end
end
