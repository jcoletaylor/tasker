# Demo Product model for the e-commerce example
class Product < ApplicationRecord
  validates :name, presence: true
  validates :price, presence: true, numericality: { greater_than: 0 }
  validates :stock, presence: true, numericality: { greater_than_or_equal_to: 0 }
  
  scope :active, -> { where(active: true) }
  scope :in_stock, -> { where('stock > 0') }
  
  def active?
    active
  end
  
  def in_stock?
    stock > 0
  end
  
  def sufficient_stock?(quantity)
    stock >= quantity
  end
end

# Migration for Product model
# 
# class CreateProducts < ActiveRecord::Migration[7.0]
#   def change
#     create_table :products do |t|
#       t.string :name, null: false
#       t.text :description
#       t.decimal :price, precision: 10, scale: 2, null: false
#       t.integer :stock, default: 0, null: false
#       t.boolean :active, default: true, null: false
#       t.string :sku
#       t.string :category
#       t.decimal :weight, precision: 8, scale: 2
#       
#       t.timestamps
#     end
#     
#     add_index :products, :sku, unique: true
#     add_index :products, :active
#     add_index :products, :category
#   end
# end
