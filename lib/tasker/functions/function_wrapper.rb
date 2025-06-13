# frozen_string_literal: true

module Tasker
  module Functions
    # Utility class for wrapping SQL function results in ActiveRecord-like objects
    class FunctionWrapper
      include ActiveModel::Model
      include ActiveModel::Attributes

      def self.from_sql_function(sql, binds = [], name = nil)
        # Convert Ruby arrays to PostgreSQL array format for bind parameters
        processed_binds = binds.map { |bind| convert_array_bind(bind) }
        results = connection.select_all(sql, name, processed_binds)
        results.map { |row| new(row) }
      end

      def self.single_from_sql_function(sql, binds = [], name = nil)
        # Convert Ruby arrays to PostgreSQL array format for bind parameters
        processed_binds = binds.map { |bind| convert_array_bind(bind) }
        result = connection.select_one(sql, name, processed_binds)
        result ? new(result) : nil
      end

      def self.convert_array_bind(bind)
        if bind.is_a?(Array)
          # Convert Ruby array to PostgreSQL array format
          "{#{bind.join(',')}}"
        else
          bind
        end
      end

      def readonly?
        true
      end

      def self.connection
        ::Tasker::ApplicationRecord.connection
      end
    end
  end
end
