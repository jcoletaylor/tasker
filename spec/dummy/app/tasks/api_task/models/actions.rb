# frozen_string_literal: true

require_relative 'types'

module ApiTask
  module Actions
    API_TASK_DATA_PATH = Rails.root.join('app/tasks/api_task/data')
    class Cart
      def self.all
        @all ||= JSON.parse(API_TASK_DATA_PATH.join('carts.json').read)['carts'].map do |cart|
          ApiTask::Cart.new(cart.deep_symbolize_keys)
        end
      end

      def self.find(id)
        all.find { |cart| cart.id == id }
      end
    end

    class Product
      def self.all
        @all ||= JSON.parse(API_TASK_DATA_PATH.join('products.json').read)['products'].map do |product|
          ApiTask::Product.new(product.deep_symbolize_keys)
        end
      end

      def self.find(id)
        all.find { |product| product.id == id }
      end
    end
  end
end
