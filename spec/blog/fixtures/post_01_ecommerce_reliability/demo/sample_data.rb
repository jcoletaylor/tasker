# Sample data setup for the e-commerce demo
class SampleDataSetup
  def self.create_sample_products
    products = [
      {
        name: "Wireless Bluetooth Headphones",
        description: "High-quality wireless headphones with noise cancellation",
        price: 129.99,
        stock: 25,
        sku: "WBH-001",
        category: "Electronics",
        weight: 0.5
      },
      {
        name: "Organic Cotton T-Shirt",
        description: "Comfortable, eco-friendly cotton t-shirt",
        price: 24.99,
        stock: 100,
        sku: "OCT-001",
        category: "Clothing",
        weight: 0.2
      },
      {
        name: "Stainless Steel Water Bottle",
        description: "Insulated water bottle that keeps drinks cold for 24 hours",
        price: 34.99,
        stock: 50,
        sku: "SSW-001",
        category: "Home & Garden",
        weight: 0.8
      },
      {
        name: "Yoga Exercise Mat",
        description: "Non-slip yoga mat for exercise and meditation",
        price: 39.99,
        stock: 30,
        sku: "YEM-001",
        category: "Sports & Outdoors",
        weight: 1.2
      },
      {
        name: "Coffee Bean Grinder",
        description: "Electric burr grinder for fresh coffee beans",
        price: 89.99,
        stock: 15,
        sku: "CBG-001",
        category: "Kitchen",
        weight: 2.1
      },
      {
        name: "Reading Glasses",
        description: "Blue light blocking reading glasses",
        price: 19.99,
        stock: 75,
        sku: "RG-001",
        category: "Health & Beauty",
        weight: 0.1
      },
      {
        name: "Desk Organizer",
        description: "Bamboo desk organizer with multiple compartments",
        price: 29.99,
        stock: 40,
        sku: "DO-001",
        category: "Office Supplies",
        weight: 0.9
      },
      {
        name: "Phone Case",
        description: "Protective phone case with wireless charging support",
        price: 15.99,
        stock: 200,
        sku: "PC-001",
        category: "Electronics",
        weight: 0.1
      }
    ]
    
    products.each do |product_data|
      Product.find_or_create_by(sku: product_data[:sku]) do |product|
        product.assign_attributes(product_data)
      end
    end
    
    puts "Created #{products.length} sample products"
  end
  
  def self.create_sample_test_scenarios
    scenarios = {
      successful_checkout: {
        cart_items: [
          { product_id: 1, quantity: 2 },  # Wireless Headphones x2
          { product_id: 3, quantity: 1 }   # Water Bottle x1
        ],
        payment_info: {
          token: "test_success_visa_4242424242424242",
          amount: 294.97  # (129.99 * 2) + 34.99 + tax + shipping
        },
        customer_info: {
          email: "test@example.com",
          name: "Test Customer",
          phone: "555-123-4567"
        }
      },
      
      payment_failure: {
        cart_items: [
          { product_id: 2, quantity: 3 }  # T-Shirts x3
        ],
        payment_info: {
          token: "test_insufficient_funds",
          amount: 85.04  # 24.99 * 3 + tax + shipping
        },
        customer_info: {
          email: "test_fail@example.com",
          name: "Test Failure Customer"
        }
      },
      
      inventory_conflict: {
        cart_items: [
          { product_id: 5, quantity: 20 }  # More grinders than in stock
        ],
        payment_info: {
          token: "test_success_mastercard",
          amount: 1814.79
        },
        customer_info: {
          email: "test_inventory@example.com",
          name: "Inventory Test Customer"
        }
      },
      
      timeout_scenario: {
        cart_items: [
          { product_id: 4, quantity: 1 }  # Yoga Mat x1
        ],
        payment_info: {
          token: "test_timeout_slow_gateway",
          amount: 48.19
        },
        customer_info: {
          email: "test_timeout@example.com",
          name: "Timeout Test Customer"
        }
      }
    }
    
    puts "Sample test scenarios created:"
    scenarios.each do |scenario_name, data|
      puts "  #{scenario_name}: #{data[:cart_items].length} items, $#{data[:payment_info][:amount]}"
    end
    
    scenarios
  end
  
  def self.create_sample_orders
    # Create a few completed orders for demonstration
    sample_orders = [
      {
        customer_email: "john.doe@example.com",
        customer_name: "John Doe",
        customer_phone: "555-987-6543",
        subtotal: 159.98,
        tax_amount: 12.80,
        shipping_amount: 9.99,
        total_amount: 182.77,
        payment_id: "pi_demo_completed_001",
        payment_status: "completed",
        transaction_id: "txn_demo_001",
        items: [
          { product_id: 1, name: "Wireless Bluetooth Headphones", price: 129.99, quantity: 1, line_total: 129.99 },
          { product_id: 6, name: "Reading Glasses", price: 19.99, quantity: 1, line_total: 19.99 },
          { product_id: 8, name: "Phone Case", price: 15.99, quantity: 1, line_total: 15.99 }
        ],
        item_count: 3,
        status: "confirmed",
        order_number: "ORD-#{Date.current.strftime('%Y%m%d')}-DEMO01",
        placed_at: 2.hours.ago
      },
      {
        customer_email: "jane.smith@example.com",
        customer_name: "Jane Smith",
        subtotal: 64.98,
        tax_amount: 5.20,
        shipping_amount: 9.99,
        total_amount: 80.17,
        payment_id: "pi_demo_completed_002",
        payment_status: "completed",
        transaction_id: "txn_demo_002",
        items: [
          { product_id: 2, name: "Organic Cotton T-Shirt", price: 24.99, quantity: 2, line_total: 49.98 },
          { product_id: 8, name: "Phone Case", price: 15.99, quantity: 1, line_total: 15.99 }
        ],
        item_count: 3,
        status: "processing",
        order_number: "ORD-#{Date.current.strftime('%Y%m%d')}-DEMO02",
        placed_at: 1.day.ago
      }
    ]
    
    sample_orders.each do |order_data|
      Order.find_or_create_by(order_number: order_data[:order_number]) do |order|
        order.assign_attributes(order_data)
      end
    end
    
    puts "Created #{sample_orders.length} sample orders"
  end
  
  def self.setup_all
    create_sample_products
    create_sample_orders
    test_scenarios = create_sample_test_scenarios
    
    puts "\n=== E-commerce Demo Setup Complete ==="
    puts "Products: #{Product.count}"
    puts "Orders: #{Order.count}"
    puts "Test scenarios: #{test_scenarios.keys.join(', ')}"
    puts "\nYou can now run checkout workflows using the sample data!"
  end
end

# Usage:
# SampleDataSetup.setup_all
