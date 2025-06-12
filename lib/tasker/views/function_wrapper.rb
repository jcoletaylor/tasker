# frozen_string_literal: true

module Tasker
  module Views
    # Utility class for wrapping SQL function results in ActiveRecord-like objects
    class FunctionWrapper
      include ActiveModel::Model
      include ActiveModel::Attributes

      def self.from_sql_function(sql, binds = [], name = nil)
        results = connection.select_all(sql, name, binds)
        results.map { |row| new(row) }
      end

      def self.single_from_sql_function(sql, binds = [], name = nil)
        result = connection.select_one(sql, name, binds)
        result ? new(result) : nil
      end

      def readonly?
        true
      end

      private

      def self.connection
        ActiveRecord::Base.connection
      end
    end
  end
end
