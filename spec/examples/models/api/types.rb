# frozen_string_literal: true

require 'dry-struct'
require 'dry-types'

module Api
  module Types
    include Dry.Types()

    # Custom types for nested structures
    Dimensions = Types::Hash.schema(
      width: Types::Coercible::Float,
      height: Types::Coercible::Float,
      depth: Types::Coercible::Float
    )

    Review = Types::Hash.schema(
      rating: Types::Coercible::Integer.optional.default(nil),
      comment: Types::String.optional.default(nil),
      date: Types::String.optional.default(nil),
      reviewer_name: Types::String.optional.default(nil),
      reviewer_email: Types::String.optional.default(nil)
    )

    Meta = Types::Hash.schema(
      created_at: Types::String.optional.default(nil),
      updated_at: Types::String.optional.default(nil),
      barcode: Types::String.optional.default(nil),
      qr_code: Types::String.optional.default(nil)
    )
  end

  class Product < Dry::Struct
    attribute :id, Types::Coercible::Integer
    attribute :title, Types::String
    attribute :description, Types::String
    attribute :category, Types::String
    attribute :price, Types::Coercible::Float
    attribute :discount_percentage, Types::Coercible::Float.optional.default(nil)
    attribute :rating, Types::Coercible::Float.optional.default(nil)
    attribute :stock, Types::Coercible::Integer
    attribute :tags, Types::Array.of(Types::String)
    attribute :brand, Types::String.optional.default(nil)
    attribute :sku, Types::String
    attribute :weight, Types::Coercible::Integer.optional.default(nil)
    attribute :dimensions, Types::Dimensions.optional.default(nil)
    attribute :warranty_information, Types::String.optional.default(nil)
    attribute :shipping_information, Types::String.optional.default(nil)
    attribute :availability_status, Types::String.optional.default(nil)
    attribute :reviews, Types::Array.of(Types::Review).optional.default(nil)
    attribute :return_policy, Types::String.optional.default(nil)
    attribute :minimum_order_quantity, Types::Coercible::Integer.optional.default(nil)
    attribute :meta, Types::Meta.optional.default(nil)
    attribute :images, Types::Array.of(Types::String).optional.default(nil)
    attribute :thumbnail, Types::String.optional.default(nil)
  end

  class CartProduct < Dry::Struct
    attribute :id, Types::Coercible::Integer
    attribute :quantity, Types::Coercible::Integer
    attribute :discount_percentage, Types::Coercible::Float.optional.default(nil)
  end

  class Cart < Dry::Struct
    attribute :id, Types::Coercible::Integer
    attribute :products, Types::Array.of(CartProduct)
    attribute :user_id, Types::Coercible::Integer
    attribute :total_products, Types::Coercible::Integer
    attribute :total_quantity, Types::Coercible::Integer
  end
end
