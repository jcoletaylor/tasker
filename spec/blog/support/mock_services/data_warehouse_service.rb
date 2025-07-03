# frozen_string_literal: true

# Mock Data Warehouse Service for Post 02: Data Pipeline Resilience
# Simulates database connections, data extraction, and transformation operations

class MockDataWarehouseService < BaseMockService
  # Error classes that step handlers expect to catch
  class TimeoutError < StandardError; end
  class ConnectionError < StandardError; end
  class InvalidQueryError < StandardError; end
  class AuthenticationError < StandardError; end
  class InsufficientDataError < StandardError; end

  # Simulated data stores
  ORDERS_DATA = [
    { id: 1, user_id: 101, product_id: 201, amount: 89.99, created_at: '2024-01-15', status: 'completed' },
    { id: 2, user_id: 102, product_id: 202, amount: 149.50, created_at: '2024-01-16', status: 'completed' },
    { id: 3, user_id: 103, product_id: 203, amount: 299.99, created_at: '2024-01-17', status: 'completed' },
    { id: 4, user_id: 101, product_id: 204, amount: 49.99, created_at: '2024-01-18', status: 'refunded' },
    { id: 5, user_id: 104, product_id: 201, amount: 89.99, created_at: '2024-01-19', status: 'completed' },
    { id: 6, user_id: 105, product_id: 205, amount: 199.99, created_at: '2024-01-20', status: 'completed' }
  ].freeze

  USERS_DATA = [
    { id: 101, email: 'alice@example.com', name: 'Alice Johnson', created_at: '2023-12-01', segment: 'premium' },
    { id: 102, email: 'bob@example.com', name: 'Bob Smith', created_at: '2023-11-15', segment: 'standard' },
    { id: 103, email: 'carol@example.com', name: 'Carol Davis', created_at: '2024-01-10', segment: 'premium' },
    { id: 104, email: 'david@example.com', name: 'David Wilson', created_at: '2023-10-05', segment: 'standard' },
    { id: 105, email: 'eve@example.com', name: 'Eve Brown', created_at: '2024-01-05', segment: 'premium' }
  ].freeze

  PRODUCTS_DATA = [
    { id: 201, name: 'Premium Widget', category: 'widgets', price: 89.99, inventory: 45 },
    { id: 202, name: 'Deluxe Gadget', category: 'gadgets', price: 149.50, inventory: 23 },
    { id: 203, name: 'Enterprise Tool', category: 'tools', price: 299.99, inventory: 12 },
    { id: 204, name: 'Basic Widget', category: 'widgets', price: 49.99, inventory: 78 },
    { id: 205, name: 'Pro Gadget', category: 'gadgets', price: 199.99, inventory: 34 }
  ].freeze

  # Extract orders data with date filtering
  def self.extract_orders(start_date:, end_date:, **)
    instance = new
    instance.extract_orders_call(start_date: start_date, end_date: end_date, **)
  end

  # Extract users data from CRM
  def self.extract_users(**)
    instance = new
    instance.extract_users_call(**)
  end

  # Extract products data from inventory system
  def self.extract_products(**)
    instance = new
    instance.extract_products_call(**)
  end

  # Transform customer metrics
  def self.transform_customer_metrics(orders_data:, users_data:, **)
    instance = new
    instance.transform_customer_metrics_call(orders_data: orders_data, users_data: users_data, **)
  end

  # Transform product metrics
  def self.transform_product_metrics(orders_data:, products_data:, **)
    instance = new
    instance.transform_product_metrics_call(orders_data: orders_data, products_data: products_data, **)
  end

  # Generate business insights
  def self.generate_insights(customer_metrics:, product_metrics:, **)
    instance = new
    instance.generate_insights_call(customer_metrics: customer_metrics, product_metrics: product_metrics, **)
  end

  # Instance methods for actual processing
  def extract_orders_call(start_date:, end_date:, **options)
    log_call(:extract_orders, { start_date: start_date, end_date: end_date, options: options })

    # Filter orders by date range
    filtered_orders = ORDERS_DATA.select do |order|
      order_date = Date.parse(order[:created_at])
      order_date.between?(Date.parse(start_date), Date.parse(end_date))
    end

    default_response = {
      status: 'success',
      data: filtered_orders,
      metadata: {
        total_records: filtered_orders.length,
        date_range: { start_date: start_date, end_date: end_date },
        extraction_time: Time.current.iso8601
      }
    }

    handle_response(:extract_orders, default_response)
  end

  def extract_users_call(**options)
    log_call(:extract_users, options)

    default_response = {
      status: 'success',
      data: USERS_DATA,
      metadata: {
        total_records: USERS_DATA.length,
        source: 'crm_api',
        extraction_time: Time.current.iso8601
      }
    }

    handle_response(:extract_users, default_response)
  end

  def extract_products_call(**options)
    log_call(:extract_products, options)

    default_response = {
      status: 'success',
      data: PRODUCTS_DATA,
      metadata: {
        total_records: PRODUCTS_DATA.length,
        source: 'inventory_system',
        extraction_time: Time.current.iso8601
      }
    }

    handle_response(:extract_products, default_response)
  end

  def transform_customer_metrics_call(orders_data:, users_data:, **options)
    log_call(:transform_customer_metrics, {
               orders_count: orders_data&.length || 0,
               users_count: users_data&.length || 0,
               options: options
             })

    # Calculate customer metrics
    customer_metrics = users_data.map do |user|
      user_orders = orders_data.select { |order| order[:user_id] == user[:id] }
      completed_orders = user_orders.select { |order| order[:status] == 'completed' }

      {
        user_id: user[:id],
        email: user[:email],
        segment: user[:segment],
        total_orders: user_orders.length,
        completed_orders: completed_orders.length,
        total_revenue: completed_orders.sum { |order| order[:amount] },
        avg_order_value: if completed_orders.empty?
                           0
                         else
                           completed_orders.sum do |order|
                             order[:amount]
                           end / completed_orders.length
                         end
      }
    end

    default_response = {
      status: 'success',
      data: customer_metrics,
      metadata: {
        total_customers: customer_metrics.length,
        transformation_time: Time.current.iso8601
      }
    }

    handle_response(:transform_customer_metrics, default_response)
  end

  def transform_product_metrics_call(orders_data:, products_data:, **options)
    log_call(:transform_product_metrics, {
               orders_count: orders_data&.length || 0,
               products_count: products_data&.length || 0,
               options: options
             })

    # Calculate product metrics
    product_metrics = products_data.map do |product|
      product_orders = orders_data.select { |order| order[:product_id] == product[:id] }
      completed_orders = product_orders.select { |order| order[:status] == 'completed' }

      {
        product_id: product[:id],
        name: product[:name],
        category: product[:category],
        total_orders: product_orders.length,
        completed_orders: completed_orders.length,
        total_revenue: completed_orders.sum { |order| order[:amount] },
        conversion_rate: product_orders.empty? ? 0 : (completed_orders.length.to_f / product_orders.length * 100).round(2)
      }
    end

    default_response = {
      status: 'success',
      data: product_metrics,
      metadata: {
        total_products: product_metrics.length,
        transformation_time: Time.current.iso8601
      }
    }

    handle_response(:transform_product_metrics, default_response)
  end

  def generate_insights_call(customer_metrics:, product_metrics:, **options)
    log_call(:generate_insights, {
               customer_count: customer_metrics&.length || 0,
               product_count: product_metrics&.length || 0,
               options: options
             })

    # Generate insights
    insights = {
      top_customers: customer_metrics.sort_by { |c| -(c[:total_revenue] || 0) }.first(3),
      top_products: product_metrics.sort_by { |p| -(p[:total_revenue] || 0) }.first(3),
      segment_analysis: {
        premium_customers: customer_metrics.count { |c| c[:segment] == 'premium' },
        standard_customers: customer_metrics.count { |c| c[:segment] == 'standard' }
      },
      category_performance: product_metrics.group_by { |p| p[:category] }
                                           .transform_values { |products| products.sum { |p| p[:total_revenue] || 0 } }
    }

    default_response = {
      status: 'success',
      data: insights,
      metadata: {
        generated_at: Time.current.iso8601,
        insights_count: insights.keys.length
      }
    }

    handle_response(:generate_insights, default_response)
  end
end
