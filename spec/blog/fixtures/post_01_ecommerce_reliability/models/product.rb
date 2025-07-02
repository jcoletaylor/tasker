# Demo Product model for the e-commerce example
# Using PORO with ActiveModel concerns to avoid ActiveRecord conflicts
module BlogExamples
  module Post01
    class Product
      include ActiveModel::Model
      include ActiveModel::Attributes
      include ActiveModel::Validations

      # Define attributes
      attribute :id, :integer
      attribute :name, :string
      attribute :description, :string
      attribute :price, :decimal
      attribute :stock, :integer, default: 0
      attribute :active, :boolean, default: true
      attribute :sku, :string
      attribute :category, :string
      attribute :weight, :decimal
      attribute :created_at, :datetime
      attribute :updated_at, :datetime

      # Validations
      validates :name, presence: true
      validates :price, presence: true, numericality: { greater_than: 0 }
      validates :stock, presence: true, numericality: { greater_than_or_equal_to: 0 }

      # Class methods for finding products (mock implementations)
      def self.find(id)
        find_by(id: id)
      end

      def self.find_by(attributes)
        # In a real test, this would use mock data or the actual Tasker database
        # Return mock products that match the test context expectations
        if attributes[:id]
          case attributes[:id]
          when 1
            new(
              id: 1,
              name: "Widget A",
              price: 29.99,
              stock: 10,
              active: true,
              sku: "WIDGET-A"
            )
          when 2
            new(
              id: 2,
              name: "Widget B",
              price: 49.99,
              stock: 10,
              active: true,
              sku: "WIDGET-B"
            )
          else
            new(
              id: attributes[:id],
              name: "Mock Product #{attributes[:id]}",
              price: 29.99,
              stock: 10,
              active: true,
              sku: "MOCK-#{attributes[:id]}"
            )
          end
        end
      end

      def self.active
        # Mock scope - in real tests this would query actual data
        []
      end

      def self.in_stock
        # Mock scope - in real tests this would query actual data
        []
      end

      # Instance methods
      def active?
        active
      end

      def in_stock?
        stock > 0
      end

      def sufficient_stock?(quantity)
        stock >= quantity
      end

      # Simulate ActiveRecord's update! method for compatibility with blog example code
      def update!(new_attributes)
        new_attributes.each do |key, value|
          send("#{key}=", value) if respond_to?("#{key}=")
        end
        self
      end
    end
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
