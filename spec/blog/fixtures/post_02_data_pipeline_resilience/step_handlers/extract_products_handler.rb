module DataPipeline
  module StepHandlers
    class ExtractProductsHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        date_range = task.context['date_range']
        start_date = Date.parse(date_range['start_date'])
        end_date = Date.parse(date_range['end_date'])
        force_refresh = task.context['force_refresh'] || false
        
        # Check cache first unless force refresh
        cached_data = get_cached_extraction('products', start_date, end_date)
        return cached_data if cached_data && !force_refresh
        
        # Get products that were ordered during the date range
        ordered_product_ids = get_ordered_product_ids(start_date, end_date)
        total_count = ordered_product_ids.length
        processed_count = 0
        
        products = []
        
        # Process in batches
        ordered_product_ids.each_slice(1000) do |product_id_batch|
          begin
            # Fetch product data from inventory system
            batch_products = fetch_products_from_inventory(product_id_batch)
            
            product_data = batch_products.map do |product|
              {
                product_id: product['id'],
                name: product['name'],
                description: product['description'],
                category: product['category'],
                subcategory: product['subcategory'],
                price: product['price'],
                cost: product['cost'],
                inventory: {
                  current_stock: product['stock_quantity'],
                  reorder_level: product['reorder_level'],
                  warehouse_location: product['warehouse_location']
                },
                attributes: {
                  brand: product['brand'],
                  color: product['color'],
                  size: product['size'],
                  weight: product['weight'],
                  dimensions: product['dimensions']
                },
                performance_metrics: calculate_product_performance(product['id'], start_date, end_date),
                created_at: product['created_at'],
                updated_at: product['updated_at']
              }
            end
            
            products.concat(product_data)
            processed_count += product_id_batch.length
            
            # Update progress for monitoring
            progress_percent = (processed_count.to_f / total_count * 100).round(1)
            update_progress_annotation(
              step, 
              "Processed #{processed_count}/#{total_count} products (#{progress_percent}%)"
            )
            
            # Brief pause to avoid overwhelming inventory system
            sleep(0.1)
            
          rescue Net::TimeoutError => e
            raise Tasker::RetryableError, "Inventory API timeout: #{e.message}"
          rescue StandardError => e
            Rails.logger.error "Product extraction error: #{e.class} - #{e.message}"
            raise Tasker::RetryableError, "Product extraction failed, will retry: #{e.message}"
          end
        end
        
        result = {
          products: products,
          total_count: products.length,
          date_range: {
            start_date: start_date.iso8601,
            end_date: end_date.iso8601
          },
          extracted_at: Time.current.iso8601,
          data_quality: {
            products_with_sales: products.count { |p| p[:performance_metrics][:units_sold] > 0 },
            avg_inventory_level: products.sum { |p| p[:inventory][:current_stock] } / products.length.to_f,
            categories_represented: products.map { |p| p[:category] }.uniq.length,
            low_stock_products: products.count { |p| 
              p[:inventory][:current_stock] <= p[:inventory][:reorder_level] 
            }
          }
        }
        
        # Cache the result
        cache_extraction('products', start_date, end_date, result)
        
        result
      end
      
      private
      
      def get_ordered_product_ids(start_date, end_date)
        OrderItem.joins(:order)
                 .where(orders: { created_at: start_date..end_date })
                 .distinct
                 .pluck(:product_id)
      end
      
      def fetch_products_from_inventory(product_ids)
        # Simulate inventory system API call
        # In real implementation, this would call external inventory service
        Product.where(id: product_ids).map do |product|
          {
            'id' => product.id,
            'name' => product.name,
            'description' => product.description,
            'category' => product.category,
            'subcategory' => product.subcategory,
            'price' => product.price,
            'cost' => product.cost,
            'stock_quantity' => product.stock_quantity,
            'reorder_level' => product.reorder_level,
            'warehouse_location' => product.warehouse_location,
            'brand' => product.brand,
            'color' => product.color,
            'size' => product.size,
            'weight' => product.weight,
            'dimensions' => "#{product.length}x#{product.width}x#{product.height}",
            'created_at' => product.created_at.iso8601,
            'updated_at' => product.updated_at.iso8601
          }
        end
      end
      
      def calculate_product_performance(product_id, start_date, end_date)
        order_items = OrderItem.joins(:order)
                              .where(product_id: product_id)
                              .where(orders: { created_at: start_date..end_date })
        
        units_sold = order_items.sum(:quantity)
        revenue = order_items.sum(:line_total)
        num_orders = order_items.count
        
        {
          units_sold: units_sold,
          revenue: revenue,
          number_of_orders: num_orders,
          average_quantity_per_order: num_orders > 0 ? units_sold.to_f / num_orders : 0,
          revenue_per_unit: units_sold > 0 ? revenue / units_sold : 0
        }
      end
      
      def update_progress_annotation(step, message)
        step.annotations.merge!({
          progress_message: message,
          last_updated: Time.current.iso8601
        })
        step.save!
      end
      
      def get_cached_extraction(data_type, start_date, end_date)
        cache_key = "extraction:#{data_type}:#{start_date}:#{end_date}"
        Rails.cache.read(cache_key)
      end
      
      def cache_extraction(data_type, start_date, end_date, data)
        cache_key = "extraction:#{data_type}:#{start_date}:#{end_date}"
        Rails.cache.write(cache_key, data, expires_in: 6.hours)
      end
    end
  end
end