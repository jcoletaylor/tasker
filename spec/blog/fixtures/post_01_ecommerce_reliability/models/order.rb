# Demo Order model for the e-commerce example
class Order < ApplicationRecord
  validates :customer_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :customer_name, presence: true
  validates :total_amount, presence: true, numericality: { greater_than: 0 }
  validates :order_number, presence: true, uniqueness: true
  validates :status, presence: true
  
  enum status: {
    pending: 'pending',
    confirmed: 'confirmed',
    processing: 'processing',
    shipped: 'shipped',
    delivered: 'delivered',
    cancelled: 'cancelled',
    refunded: 'refunded'
  }
  
  enum payment_status: {
    pending_payment: 'pending',
    completed: 'completed',
    failed: 'failed',
    refunded: 'refunded'
  }
  
  # JSON column for storing order items
  # Each item: { product_id, name, price, quantity, line_total }
  serialize :items, Array
  
  scope :recent, -> { order(created_at: :desc) }
  scope :for_customer, ->(email) { where(customer_email: email) }
  
  def item_count
    items.sum { |item| item['quantity'] }
  end
  
  def formatted_total
    "$%.2f" % total_amount
  end
  
  def formatted_order_number
    order_number
  end
end

# Migration for Order model
#
# class CreateOrders < ActiveRecord::Migration[7.0]
#   def change
#     create_table :orders do |t|
#       t.string :customer_email, null: false
#       t.string :customer_name, null: false
#       t.string :customer_phone
#       
#       # Order totals
#       t.decimal :subtotal, precision: 10, scale: 2, null: false
#       t.decimal :tax_amount, precision: 10, scale: 2, default: 0
#       t.decimal :shipping_amount, precision: 10, scale: 2, default: 0
#       t.decimal :total_amount, precision: 10, scale: 2, null: false
#       
#       # Payment information
#       t.string :payment_id
#       t.string :payment_status, default: 'pending'
#       t.string :transaction_id
#       
#       # Order items (JSON)
#       t.json :items, null: false
#       t.integer :item_count, default: 0
#       
#       # Inventory tracking
#       t.bigint :inventory_log_id
#       
#       # Order metadata
#       t.string :status, default: 'pending', null: false
#       t.string :order_number, null: false
#       t.datetime :placed_at
#       
#       # Workflow tracking
#       t.bigint :task_id
#       t.string :workflow_version
#       
#       t.timestamps
#     end
#     
#     add_index :orders, :customer_email
#     add_index :orders, :order_number, unique: true
#     add_index :orders, :status
#     add_index :orders, :payment_status
#     add_index :orders, :task_id
#     add_index :orders, :placed_at
#   end
# end
