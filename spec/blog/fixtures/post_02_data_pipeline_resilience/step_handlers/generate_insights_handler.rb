module DataPipeline
  module StepHandlers
    class GenerateInsightsHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        customer_metrics_data = step_results(sequence, 'transform_customer_metrics')
        product_metrics_data = step_results(sequence, 'transform_product_metrics')
        
        customer_metrics = customer_metrics_data['customer_metrics'] || []
        product_metrics = product_metrics_data['product_metrics'] || []
        
        insights = {
          executive_summary: generate_executive_summary(customer_metrics, product_metrics),
          customer_insights: generate_customer_insights(customer_metrics),
          product_insights: generate_product_insights(product_metrics),
          business_recommendations: generate_business_recommendations(customer_metrics, product_metrics),
          performance_alerts: generate_performance_alerts(customer_metrics, product_metrics),
          generated_at: Time.current.iso8601
        }
        
        update_progress_annotation(step, "Generated comprehensive business insights")
        
        insights
      end
      
      private
      
      def step_results(sequence, step_name)
        step = sequence.steps.find { |s| s.name == step_name }
        step&.result || {}
      end
      
      def generate_executive_summary(customer_metrics, product_metrics)
        total_customers = customer_metrics.length
        total_products = product_metrics.length
        
        total_revenue = product_metrics.sum { |p| p.dig('performance', 'total_revenue') || 0 }
        total_profit = product_metrics.sum { |p| p.dig('profitability', 'total_profit') || 0 }
        
        avg_clv = customer_metrics.sum { |c| c['total_lifetime_value'] || 0 } / total_customers.to_f
        
        vip_customers = customer_metrics.count { |c| c['customer_segment'] == 'VIP' }
        new_customers = customer_metrics.count { |c| c['customer_segment'] == 'New' }
        
        top_category = product_metrics.group_by { |p| p['category'] }
                                     .transform_values { |products| products.sum { |p| p.dig('performance', 'total_revenue') || 0 } }
                                     .max_by { |category, revenue| revenue }
                                     &.first
        
        {
          period_overview: {
            total_customers_analyzed: total_customers,
            total_products_analyzed: total_products,
            total_revenue: total_revenue.round(2),
            total_profit: total_profit.round(2),
            profit_margin: total_revenue > 0 ? (total_profit / total_revenue * 100).round(2) : 0
          },
          customer_highlights: {
            average_customer_lifetime_value: avg_clv.round(2),
            vip_customers_count: vip_customers,
            vip_customers_percentage: total_customers > 0 ? (vip_customers.to_f / total_customers * 100).round(1) : 0,
            new_customers_count: new_customers,
            customer_retention_opportunity: total_customers - vip_customers - new_customers
          },
          product_highlights: {
            top_performing_category: top_category,
            products_needing_reorder: product_metrics.count { |p| p.dig('inventory', 'reorder_recommended') },
            high_margin_products: product_metrics.count { |p| (p.dig('profitability', 'profit_margin_percent') || 0) > 30 }
          }
        }
      end
      
      def generate_customer_insights(customer_metrics)
        return {} if customer_metrics.empty?
        
        # Segment analysis
        segments = customer_metrics.group_by { |c| c['customer_segment'] }
        segment_analysis = segments.transform_values do |customers|
          {
            count: customers.length,
            avg_lifetime_value: (customers.sum { |c| c['total_lifetime_value'] } / customers.length.to_f).round(2),
            avg_order_frequency: (customers.sum { |c| c['order_frequency'] } / customers.length.to_f).round(2),
            avg_orders: (customers.sum { |c| c['total_orders'] } / customers.length.to_f).round(1)
          }
        end
        
        # Churn risk analysis
        at_risk_customers = customer_metrics.select { |c| (c['days_since_last_order'] || 0) > 90 }
        
        # High value customer analysis
        high_value_customers = customer_metrics.select { |c| c['total_lifetime_value'] > 500 }
        
        {
          segmentation: segment_analysis,
          churn_risk: {
            customers_at_risk: at_risk_customers.length,
            at_risk_revenue: at_risk_customers.sum { |c| c['total_lifetime_value'] }.round(2),
            avg_days_since_last_order: at_risk_customers.sum { |c| c['days_since_last_order'] || 0 } / [at_risk_customers.length, 1].max
          },
          high_value_analysis: {
            high_value_customer_count: high_value_customers.length,
            high_value_revenue_percentage: customer_metrics.sum { |c| c['total_lifetime_value'] } > 0 ? 
              (high_value_customers.sum { |c| c['total_lifetime_value'] } / customer_metrics.sum { |c| c['total_lifetime_value'] } * 100).round(1) : 0,
            avg_high_value_clv: high_value_customers.empty? ? 0 : (high_value_customers.sum { |c| c['total_lifetime_value'] } / high_value_customers.length).round(2)
          },
          marketing_insights: {
            email_opt_in_opportunities: customer_metrics.count { |c| !c.dig('marketing_preferences', 'email_opt_in') },
            recent_customers_needing_engagement: customer_metrics.count { |c| 
              c['customer_segment'] == 'New' && (c['days_since_last_order'] || 0) > 30 
            }
          }
        }
      end
      
      def generate_product_insights(product_metrics)
        return {} if product_metrics.empty?
        
        # Performance analysis
        top_performers = product_metrics.sort_by { |p| p.dig('performance', 'total_revenue') || 0 }.reverse.first(5)
        underperformers = product_metrics.select { |p| (p.dig('performance', 'total_units_sold') || 0) < 5 }
        
        # Profitability analysis
        high_margin_products = product_metrics.select { |p| (p.dig('profitability', 'profit_margin_percent') || 0) > 50 }
        low_margin_products = product_metrics.select { |p| (p.dig('profitability', 'profit_margin_percent') || 0) < 10 }
        
        # Inventory analysis
        reorder_needed = product_metrics.select { |p| p.dig('inventory', 'reorder_recommended') }
        fast_movers = product_metrics.select { |p| (p.dig('inventory', 'inventory_turnover') || 0) > 5 }
        slow_movers = product_metrics.select { |p| (p.dig('inventory', 'inventory_turnover') || 0) < 1 }
        
        # Category analysis
        category_performance = product_metrics.group_by { |p| p['category'] }
                                             .transform_values do |products|
          {
            product_count: products.length,
            total_revenue: products.sum { |p| p.dig('performance', 'total_revenue') || 0 }.round(2),
            avg_margin: products.sum { |p| p.dig('profitability', 'profit_margin_percent') || 0 } / products.length.to_f
          }
        end
        
        {
          performance: {
            top_performers: top_performers.map { |p| 
              { 
                name: p['product_name'], 
                revenue: p.dig('performance', 'total_revenue'),
                units_sold: p.dig('performance', 'total_units_sold')
              } 
            },
            underperformers_count: underperformers.length,
            underperformers_percentage: (underperformers.length.to_f / product_metrics.length * 100).round(1)
          },
          profitability: {
            high_margin_products_count: high_margin_products.length,
            high_margin_revenue: high_margin_products.sum { |p| p.dig('performance', 'total_revenue') || 0 }.round(2),
            low_margin_products_count: low_margin_products.length,
            avg_profit_margin: product_metrics.sum { |p| p.dig('profitability', 'profit_margin_percent') || 0 } / product_metrics.length.to_f
          },
          inventory: {
            reorder_needed_count: reorder_needed.length,
            reorder_needed_products: reorder_needed.map { |p| 
              { 
                name: p['product_name'], 
                current_stock: p.dig('inventory', 'current_stock'),
                reorder_level: p.dig('inventory', 'reorder_level')
              } 
            }.first(10),
            fast_movers_count: fast_movers.length,
            slow_movers_count: slow_movers.length
          },
          category_performance: category_performance
        }
      end
      
      def generate_business_recommendations(customer_metrics, product_metrics)
        recommendations = []
        
        # Customer recommendations
        at_risk_customers = customer_metrics.select { |c| (c['days_since_last_order'] || 0) > 90 }
        if at_risk_customers.length > 0
          recommendations << {
            type: 'customer_retention',
            priority: 'high',
            title: 'Re-engage At-Risk Customers',
            description: "#{at_risk_customers.length} customers haven't ordered in 90+ days. Launch re-engagement campaign.",
            impact: "Potential revenue recovery: $#{at_risk_customers.sum { |c| c['average_order_value'] || 0 }.round(2)}",
            action_items: [
              'Create targeted email campaign for dormant customers',
              'Offer special discount or incentive',
              'Survey customers to understand barriers'
            ]
          }
        end
        
        new_customers = customer_metrics.select { |c| c['customer_segment'] == 'New' }
        if new_customers.length > 0
          recommendations << {
            type: 'customer_onboarding',
            priority: 'medium',
            title: 'Improve New Customer Onboarding',
            description: "#{new_customers.length} new customers could benefit from onboarding sequence.",
            impact: "Increase repeat purchase rate from new customers",
            action_items: [
              'Create post-purchase email sequence',
              'Offer new customer education content',
              'Implement loyalty program enrollment'
            ]
          }
        end
        
        # Product recommendations
        underperformers = product_metrics.select { |p| (p.dig('performance', 'total_units_sold') || 0) < 5 }
        if underperformers.length > 0
          recommendations << {
            type: 'product_optimization',
            priority: 'medium',
            title: 'Review Underperforming Products',
            description: "#{underperformers.length} products sold fewer than 5 units. Consider pricing or promotion.",
            impact: "Improve product portfolio efficiency",
            action_items: [
              'Analyze pricing competitiveness',
              'Consider promotional campaigns',
              'Evaluate product-market fit',
              'Consider discontinuation for worst performers'
            ]
          }
        end
        
        reorder_needed = product_metrics.select { |p| p.dig('inventory', 'reorder_recommended') }
        if reorder_needed.length > 0
          recommendations << {
            type: 'inventory_management',
            priority: 'high',
            title: 'Critical Inventory Reorders Needed',
            description: "#{reorder_needed.length} products are below reorder level and need restocking.",
            impact: "Prevent stockouts and lost sales",
            action_items: [
              'Place urgent reorders for critical items',
              'Review reorder levels for accuracy',
              'Implement automated reorder system',
              'Negotiate faster supplier lead times'
            ]
          }
        end
        
        high_margin_products = product_metrics.select { |p| (p.dig('profitability', 'profit_margin_percent') || 0) > 50 }
        if high_margin_products.length > 0
          recommendations << {
            type: 'revenue_optimization',
            priority: 'medium',
            title: 'Promote High-Margin Products',
            description: "#{high_margin_products.length} products have >50% margin. Increase promotion to boost profits.",
            impact: "Maximize profitability through strategic promotion",
            action_items: [
              'Feature high-margin products in marketing',
              'Create product bundles with high-margin items',
              'Train sales team on margin leaders',
              'Optimize website placement for these products'
            ]
          }
        end
        
        recommendations
      end
      
      def generate_performance_alerts(customer_metrics, product_metrics)
        alerts = []
        
        # Customer alerts
        high_value_at_risk = customer_metrics.select { |c| 
          c['total_lifetime_value'] > 1000 && (c['days_since_last_order'] || 0) > 60 
        }
        
        if high_value_at_risk.length > 0
          alerts << {
            type: 'customer_alert',
            severity: 'critical',
            title: 'High-Value Customers At Risk',
            message: "#{high_value_at_risk.length} high-value customers (>$1000 LTV) haven't ordered in 60+ days",
            customers_affected: high_value_at_risk.length,
            revenue_at_risk: high_value_at_risk.sum { |c| c['total_lifetime_value'] }.round(2)
          }
        end
        
        # Product alerts
        critical_stock = product_metrics.select { |p| 
          p.dig('inventory', 'reorder_recommended') && p.dig('inventory', 'current_stock') == 0
        }
        
        if critical_stock.length > 0
          alerts << {
            type: 'inventory_alert',
            severity: 'critical',
            title: 'Products Out of Stock',
            message: "#{critical_stock.length} products are completely out of stock",
            products_affected: critical_stock.map { |p| p['product_name'] }.first(10)
          }
        end
        
        low_margin_high_volume = product_metrics.select { |p| 
          (p.dig('profitability', 'profit_margin_percent') || 0) < 5 && 
          (p.dig('performance', 'total_units_sold') || 0) > 50
        }
        
        if low_margin_high_volume.length > 0
          alerts << {
            type: 'profitability_alert',
            severity: 'warning',
            title: 'High-Volume Low-Margin Products',
            message: "#{low_margin_high_volume.length} popular products have <5% margin, impacting profitability",
            products_affected: low_margin_high_volume.map { |p| p['product_name'] }.first(5)
          }
        end
        
        alerts
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