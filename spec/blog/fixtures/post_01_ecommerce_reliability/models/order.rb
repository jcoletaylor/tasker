# frozen_string_literal: true

# Demo Order model for the e-commerce example
# Using PORO with ActiveModel concerns to avoid ActiveRecord conflicts
module BlogExamples
  module Post01
    class Order
      include ActiveModel::Model
      include ActiveModel::Attributes
      include ActiveModel::Validations

      # Define attributes
      attribute :id, :integer
      attribute :customer_email, :string
      attribute :customer_name, :string
      attribute :customer_phone, :string
      attribute :subtotal, :decimal
      attribute :tax_amount, :decimal, default: 0
      attribute :shipping_amount, :decimal, default: 0
      attribute :total_amount, :decimal
      attribute :payment_id, :string
      attribute :payment_status, :string, default: 'pending'
      attribute :transaction_id, :string
      attribute :items, :string # JSON serialized
      attribute :item_count, :integer, default: 0
      attribute :inventory_log_id, :integer
      attribute :status, :string, default: 'pending'
      attribute :order_number, :string
      attribute :placed_at, :datetime
      attribute :task_id, :integer
      attribute :workflow_version, :string
      attribute :created_at, :datetime
      attribute :updated_at, :datetime

      # Validations
      validates :customer_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
      validates :customer_name, presence: true
      validates :total_amount, presence: true, numericality: { greater_than: 0 }
      validates :order_number, presence: true
      validates :status, presence: true

      # Status methods (avoiding enum conflicts)
      def pending?
        status == 'pending'
      end

      def confirmed?
        status == 'confirmed'
      end

      def processing?
        status == 'processing'
      end

      def shipped?
        status == 'shipped'
      end

      def delivered?
        status == 'delivered'
      end

      def cancelled?
        status == 'cancelled'
      end

      def refunded?
        status == 'refunded'
      end

      # Payment status methods
      def payment_pending?
        payment_status == 'pending'
      end

      def payment_completed?
        payment_status == 'completed'
      end

      def payment_failed?
        payment_status == 'failed'
      end

      def payment_refunded?
        payment_status == 'refunded'
      end

      # Utility methods
      def items_array
        return [] if items.blank?

        JSON.parse(items)
      rescue JSON::ParserError
        []
      end

      def items_array=(value)
        self.items = value.to_json
        self.item_count = value.sum { |item| item['quantity'] || 0 }
      end

      def item_count
        items_array.sum { |item| item['quantity'] || 0 }
      end

      def formatted_total
        '$%.2f' % total_amount
      end

      def formatted_order_number
        order_number
      end

      # Simulate ID generation for demo purposes
      def self.next_id
        @next_id ||= 1000
        @next_id += 1
      end

      # Override initialize to set ID if not provided
      def initialize(attributes = {})
        super
        self.id ||= self.class.next_id
      end
    end
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
