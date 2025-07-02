module DataPipeline
  module StepHandlers
    class TransformProductMetricsHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        orders_data = step_results(sequence, 'extract_orders')
        products_data = step_results(sequence, 'extract_products')
        
        orders = orders_data['orders']
        products = products_data['products']
        
        # Create lookup hash for efficient product data access
        products_by_id = products.index_by { |product| product['product_id'] }
        
        # Group order items by product
        product_sales = {}
        orders.each do |order|
          order['items'].each do |item|
            product_id = item['product_id']
            product_sales[product_id] ||= []
            product_sales[product_id] << {
              order_id: order['order_id'],
              order_date: order['order_date'],
              quantity: item['quantity'],
              unit_price: item['unit_price'],
              line_total: item['line_total'],
              customer_id: order['customer_id']
            }
          end
        end
        
        product_metrics = []
        processed_products = 0
        total_products = product_sales.keys.length
        
        product_sales.each do |product_id, sales_data|
          product_info = products_by_id[product_id]
          next unless product_info  # Skip if product data missing
          
          metrics = calculate_product_metrics(product_info, sales_data)
          product_metrics << metrics
          
          processed_products += 1
          
          # Update progress every 50 products
          if processed_products % 50 == 0
            progress_percent = (processed_products.to_f / total_products * 100).round(1)
            update_progress_annotation(
              step,
              "Processed #{processed_products}/#{total_products} products (#{progress_percent}%)"
            )
          end
        end
        
        {
          product_metrics: product_metrics,
          total_products: product_metrics.length,
          metrics_calculated: %w[
            total_revenue
            total_units_sold
            average_selling_price
            profit_margin
            inventory_turnover
            top_customers
            sales_trend
          ],
          calculated_at: Time.current.iso8601
        }
      end
      
      private
      
      def step_results(sequence, step_name)
        step = sequence.steps.find { |s| s.name == step_name }
        step&.result || {}
      end
      
      def calculate_product_metrics(product_info, sales_data)
        total_revenue = sales_data.sum { |sale| sale[:line_total] }
        total_units_sold = sales_data.sum { |sale| sale[:quantity] }
        total_orders = sales_data.length
        
        # Calculate average selling price
        avg_selling_price = total_units_sold > 0 ? total_revenue / total_units_sold : 0
        
        # Calculate profit margin
        product_cost = product_info['cost'] || 0
        profit_per_unit = avg_selling_price - product_cost
        profit_margin = avg_selling_price > 0 ? (profit_per_unit / avg_selling_price * 100) : 0
        
        # Calculate inventory turnover (simplified)
        current_stock = product_info.dig('inventory', 'current_stock') || 0
        inventory_turnover = current_stock > 0 ? total_units_sold.to_f / current_stock : 0
        
        # Find top customers for this product
        customer_purchases = sales_data.group_by { |sale| sale[:customer_id] }
        top_customers = customer_purchases.map do |customer_id, purchases|
          {
            customer_id: customer_id,
            total_quantity: purchases.sum { |p| p[:quantity] },
            total_spent: purchases.sum { |p| p[:line_total] },
            order_count: purchases.length
          }
        end.sort_by { |c| c[:total_spent] }.reverse.first(5)
        
        # Calculate sales trend (daily sales)
        daily_sales = sales_data.group_by { |sale| Date.parse(sale[:order_date]).strftime('%Y-%m-%d') }
                                .transform_values { |sales| sales.sum { |s| s[:quantity] } }
        
        {
          product_id: product_info['product_id'],
          product_name: product_info['name'],
          category: product_info['category'],
          subcategory: product_info['subcategory'],
          performance: {
            total_revenue: total_revenue.round(2),
            total_units_sold: total_units_sold,
            total_orders: total_orders,
            average_selling_price: avg_selling_price.round(2),
            average_quantity_per_order: total_orders > 0 ? (total_units_sold.to_f / total_orders).round(2) : 0
          },
          profitability: {
            cost_per_unit: product_cost,
            profit_per_unit: profit_per_unit.round(2),
            profit_margin_percent: profit_margin.round(2),
            total_profit: (profit_per_unit * total_units_sold).round(2)
          },
          inventory: {
            current_stock: current_stock,
            inventory_turnover: inventory_turnover.round(2),
            days_of_inventory: inventory_turnover > 0 ? (365 / inventory_turnover).round(0) : 0,
            reorder_recommended: current_stock <= product_info.dig('inventory', 'reorder_level')
          },
          customers: {
            unique_customers: customer_purchases.keys.length,
            top_customers: top_customers,
            repeat_customer_rate: calculate_repeat_customer_rate(customer_purchases)
          },
          trends: {
            daily_sales: daily_sales,
            peak_sales_day: daily_sales.max_by { |date, quantity| quantity }&.first,
            sales_velocity: calculate_sales_velocity(daily_sales)
          },
          calculated_at: Time.current.iso8601
        }
      end
      
      def calculate_repeat_customer_rate(customer_purchases)
        return 0 if customer_purchases.empty?
        
        repeat_customers = customer_purchases.count { |customer_id, purchases| purchases.length > 1 }
        (repeat_customers.to_f / customer_purchases.length * 100).round(2)
      end
      
      def calculate_sales_velocity(daily_sales)
        return 0 if daily_sales.length < 2
        
        # Simple moving average of daily sales
        total_sales = daily_sales.values.sum
        total_sales.to_f / daily_sales.length
      end
      
      def update_progress_annotation(step, message)
        step.annotations.merge!({
          progress_message: message,
          last_updated: Time.current.iso8601
        })
        step.save!
      end
    end
  end
end