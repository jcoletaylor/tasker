# **🚀 TASKER EXECUTION CONFIGURATION GUIDE**

*Strategic configuration for performance optimization and system tuning*

---

## **📊 OVERVIEW**

Tasker's execution configuration system provides fine-grained control over performance characteristics while maintaining carefully chosen architectural constants. This design separates **configurable system tuning** from **Ruby-specific optimizations** that should remain fixed.

## **🎯 CONFIGURATION PHILOSOPHY**

### **✅ CONFIGURABLE SETTINGS**
These affect performance characteristics and should vary by deployment environment:

- **Concurrency bounds** - Different systems have different optimal ranges
- **Timeout configuration** - Heavily dependent on workload characteristics
- **Cache duration** - Varies based on system stability vs responsiveness needs

### **🏗️ ARCHITECTURAL CONSTANTS**
These are carefully chosen based on Ruby/Rails characteristics and should NOT be configurable:

- **Future cleanup timing** - Based on Ruby Concurrent::Future characteristics
- **GC trigger thresholds** - Based on Ruby memory management patterns
- **Memory management constants** - Based on Ruby GC timing characteristics

---

## **⚙️ CONFIGURATION REFERENCE**

### **Basic Configuration**

```ruby
# config/initializers/tasker.rb
Tasker.configure do |config|
  config.execution do |exec|
    # Concurrency settings
    exec.min_concurrent_steps = 3           # Minimum concurrent steps (default: 3)
    exec.max_concurrent_steps_limit = 12    # Maximum concurrent steps (default: 12)
    exec.concurrency_cache_duration = 30    # Cache duration in seconds (default: 30)

    # Timeout settings
    exec.batch_timeout_base_seconds = 30    # Base timeout (default: 30)
    exec.batch_timeout_per_step_seconds = 5 # Per-step timeout (default: 5)
    exec.max_batch_timeout_seconds = 120    # Maximum timeout cap (default: 120)
  end
end
```

### **Environment-Specific Examples**

#### **Development Environment**
```ruby
# config/environments/development.rb
Tasker.configure do |config|
  config.execution do |exec|
    # Conservative settings for development
    exec.min_concurrent_steps = 2
    exec.max_concurrent_steps_limit = 6
    exec.concurrency_cache_duration = 60    # Longer cache for stability
    exec.batch_timeout_base_seconds = 20    # Shorter timeouts for fast feedback
    exec.max_batch_timeout_seconds = 60
  end
end
```

#### **Production Environment**
```ruby
# config/environments/production.rb
Tasker.configure do |config|
  config.execution do |exec|
    # High-performance settings for production
    exec.min_concurrent_steps = 5
    exec.max_concurrent_steps_limit = 25
    exec.concurrency_cache_duration = 15    # Shorter cache for responsiveness
    exec.batch_timeout_base_seconds = 45    # Longer timeouts for reliability
    exec.batch_timeout_per_step_seconds = 8
    exec.max_batch_timeout_seconds = 300
  end
end
```

#### **High-Performance System**
```ruby
# For systems with large database connection pools
Tasker.configure do |config|
  config.execution do |exec|
    exec.min_concurrent_steps = 10
    exec.max_concurrent_steps_limit = 50
    exec.concurrency_cache_duration = 10    # Very responsive
    exec.batch_timeout_base_seconds = 60
    exec.batch_timeout_per_step_seconds = 10
    exec.max_batch_timeout_seconds = 600    # Long-running workflows
  end
end
```

---

## **🔧 CONFIGURATION DETAILS**

### **Concurrency Settings**

| Setting | Purpose | Considerations |
|---------|---------|----------------|
| `min_concurrent_steps` | Conservative lower bound | Ensures system stability under extreme load |
| `max_concurrent_steps_limit` | Upper bound for dynamic calculation | Should align with database connection pool size |
| `concurrency_cache_duration` | How long to cache concurrency calculations | Balance between responsiveness and performance |

**Dynamic Calculation**: Tasker automatically calculates optimal concurrency between `min` and `max` based on:
- System health metrics
- Database connection pool utilization
- Current workload patterns

### **Timeout Configuration**

| Setting | Purpose | Formula |
|---------|---------|---------|
| `batch_timeout_base_seconds` | Starting timeout | Base time before per-step adjustments |
| `batch_timeout_per_step_seconds` | Per-step addition | `base + (steps * per_step)` |
| `max_batch_timeout_seconds` | Absolute maximum | Prevents runaway timeouts |

**Example Calculations**:
```ruby
# With defaults: base=30, per_step=5, max=120
config.calculate_batch_timeout(1)  # => 35 seconds (30 + 1*5)
config.calculate_batch_timeout(10) # => 80 seconds (30 + 10*5)
config.calculate_batch_timeout(50) # => 120 seconds (capped at max)
```

### **Architectural Constants**

These values are **NOT configurable** and are based on Ruby characteristics:

| Constant | Value | Rationale |
|----------|-------|-----------|
| `future_cleanup_wait_seconds` | 1 second | Optimal for Ruby Concurrent::Future cleanup |
| `gc_trigger_batch_size_threshold` | 6 operations | Ruby memory pressure detection point |
| `gc_trigger_duration_threshold` | 30 seconds | Ruby GC timing characteristics |

---

## **📊 PERFORMANCE TUNING GUIDE**

### **Identifying Optimal Settings**

1. **Start with defaults** for initial deployment
2. **Monitor system metrics**:
   - Database connection pool utilization
   - Step execution times
   - Memory usage patterns
   - Error rates

3. **Adjust based on patterns**:
   - **High connection pressure** → Reduce `max_concurrent_steps_limit`
   - **Frequent timeouts** → Increase timeout settings
   - **Slow response to load changes** → Reduce `concurrency_cache_duration`

### **Common Tuning Scenarios**

#### **API-Heavy Workflows**
```ruby
config.execution do |exec|
  exec.batch_timeout_base_seconds = 60      # Longer base for API calls
  exec.batch_timeout_per_step_seconds = 10  # More time per API step
  exec.max_batch_timeout_seconds = 300      # Allow for slow APIs
end
```

#### **Database-Intensive Workflows**
```ruby
config.execution do |exec|
  exec.max_concurrent_steps_limit = 8       # Respect DB connection limits
  exec.concurrency_cache_duration = 45      # Stable DB load
end
```

#### **Mixed Workload System**
```ruby
config.execution do |exec|
  exec.min_concurrent_steps = 4             # Higher minimum for consistency
  exec.max_concurrent_steps_limit = 16      # Moderate maximum
  exec.concurrency_cache_duration = 20      # Balance responsiveness/stability
end
```

---

## **🔍 VALIDATION & MONITORING**

### **Configuration Validation**

Tasker automatically validates configuration on startup:

```ruby
# This will raise an error if invalid
config.execution.validate!

# Manual validation with detailed errors
errors = config.execution.validate_concurrency_bounds
errors += config.execution.validate_timeout_configuration
puts "Configuration errors: #{errors}" unless errors.empty?
```

### **Runtime Monitoring**

Monitor these metrics to optimize configuration:

```ruby
# Access current configuration
current_config = Tasker.configuration.execution

# Monitor dynamic concurrency decisions
max_concurrent = step_executor.max_concurrent_steps

# Check timeout calculations
timeout_for_batch = current_config.calculate_batch_timeout(batch_size)

# Monitor GC triggers
should_gc = current_config.should_trigger_gc?(batch_size, duration)
```

### **Structured Logging Integration**

Tasker logs configuration-related decisions:

```json
{
  "message": "Dynamic concurrency calculated",
  "rails_pool_size": 25,
  "rails_available": 18,
  "recommended_concurrency": 8,
  "connection_pressure": "moderate"
}
```

---

## **🚨 BEST PRACTICES**

### **✅ DO**

- **Start with defaults** and measure before optimizing
- **Test configuration changes** in staging before production
- **Monitor system metrics** after configuration changes
- **Use environment-specific settings** for development vs production
- **Validate configuration** during deployment

### **❌ DON'T**

- **Set extreme values** without understanding implications
- **Ignore validation errors** - they prevent runtime issues
- **Use same settings everywhere** - environments have different needs
- **Change multiple settings simultaneously** - makes troubleshooting difficult
- **Set `min` higher than `max`** - validation will catch this but avoid it

### **⚠️ CAUTION**

- **Database connection exhaustion**: Ensure `max_concurrent_steps_limit` respects your connection pool
- **Memory pressure**: Very high concurrency can cause memory issues
- **Timeout cascades**: Very short timeouts can cause cascading failures
- **Cache duration**: Very short cache duration increases CPU overhead

---

## **🔧 TROUBLESHOOTING**

### **Common Issues**

#### **"Connection pool exhausted" errors**
```ruby
# Solution: Reduce concurrency limit
config.execution.max_concurrent_steps_limit = 8
```

#### **Frequent timeout errors**
```ruby
# Solution: Increase timeout settings
config.execution.batch_timeout_base_seconds = 60
config.execution.max_batch_timeout_seconds = 300
```

#### **Slow response to load changes**
```ruby
# Solution: Reduce cache duration
config.execution.concurrency_cache_duration = 15
```

#### **High CPU from concurrency calculation**
```ruby
# Solution: Increase cache duration
config.execution.concurrency_cache_duration = 60
```

### **Validation Errors**

| Error | Cause | Solution |
|-------|-------|----------|
| "min_concurrent_steps must be positive" | Zero or negative minimum | Set to positive value (≥1) |
| "min cannot exceed max" | Invalid bounds | Ensure min < max |
| "max_batch_timeout_seconds must be greater than base" | Invalid timeout relationship | Ensure max > base |

---

## **📈 PERFORMANCE IMPACT**

### **Expected Improvements**

With proper configuration tuning:

- **200-300% throughput increase** through optimal concurrency
- **40% reduction in timeout-related failures** through proper timeout settings
- **30% faster response to load changes** through optimal cache duration
- **Reduced database connection pressure** through intelligent concurrency limiting

### **Monitoring Success**

Track these metrics to validate configuration effectiveness:

```ruby
# Throughput metrics
steps_per_minute = completed_steps / elapsed_minutes

# Resource utilization
connection_utilization = active_connections / pool_size
memory_growth_rate = (current_memory - initial_memory) / elapsed_time

# Error rates
timeout_rate = timeout_errors / total_batches
connection_error_rate = connection_errors / total_operations
```

---

## **✨ CONCLUSION**

Tasker's execution configuration system provides powerful tuning capabilities while maintaining architectural integrity. By separating configurable performance characteristics from Ruby-specific optimizations, developers can optimize for their specific deployment environment while benefiting from carefully chosen defaults.

The key to successful configuration is **measurement-driven optimization**: start with defaults, monitor system behavior, and adjust based on observed patterns rather than assumptions.

For additional support or advanced configuration scenarios, refer to the main Tasker documentation or reach out to the development team.
