# frozen_string_literal: true

require_relative 'types'

module Api
  class Cart
    def self.all
      @all ||= JSON.parse(Rails.root.join('../examples/data/carts.json').read)['carts'].map do |cart|
        Api::Cart.new(cart.deep_symbolize_keys)
      end
    end

    def self.find(id)
      all.find { |cart| cart.id == id }
    end
  end

  class Product
    def self.all
      @all ||= JSON.parse(Rails.root.join('../examples/data/products.json').read)['products'].map do |product|
        Api::Product.new(product.deep_symbolize_keys)
      end
    end

    def self.find(id)
      all.find { |product| product.id == id }
    end
  end
end
