# frozen_string_literal: true

class ExampleOrder
  attr_reader :id, :products, :status, :total, :discounted_total, :user_id

  def initialize(id:, products:, total:, discounted_total:, user_id:)
    @id = id
    @products = products
    @total = total
    @discounted_total = discounted_total
    @user_id = user_id
    @status = 'placed_pending_fulfillment'
  end

  def to_json(*_args)
    {
      id: id,
      products: products,
      total: total,
      discounted_total: discounted_total,
      user_id: user_id,
      status: status
    }
  end
end
