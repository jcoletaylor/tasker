# Active Context: Phase 4.2.2.3 Plugin Architecture for Custom Exporters

## 🎯 Current Focus: Extensible Export Plugin System Implementation

**Current State**: **Phase 4.2.2.3.3 Export Coordination with TTL Safety COMPLETED** with production-ready job queue architecture
**Next Target**: **Phase 4.2.2.3.4 Plugin Architecture for Custom Exporters** - Framework-appropriate extensibility

**📋 COMPREHENSIVE PLAN**: See `docs/OBSERVABILITY_ENHANCEMENT.md` Section 4.2.2.3 for complete architectural details, implementation timeline, and technical specifications.

### 📍 **Where We Are Right Now**

#### **✅ Phase 4.2.2.3.1 Cache Detection System - COMPLETED**
- **Cache Capability Detection**: Automatic identification of Rails.cache store features
- **Adaptive Strategy Selection**: `distributed_atomic`, `distributed_basic`, `local_only` based on capabilities
- **Rails Cache Integration**: Structured cache keys following Rails guide patterns
- **Store Compatibility**: Support for Redis, Memcached, Memory, File, Null stores
- **Operational Visibility**: Comprehensive logging of capabilities and strategy selection

#### **✅ Phase 4.2.2.3.2 Adaptive Sync Operations - COMPLETED**
- **Multi-Strategy Sync**: Atomic operations (Redis), read-modify-write (basic distributed), local snapshots
- **Performance Preservation**: Maintains `Concurrent::Hash` hot-path unchanged (0% regression)
- **Conflict Resolution**: Optimistic concurrency with exponential backoff retry logic
- **Error Handling**: Graceful degradation, comprehensive logging, resilience patterns
- **Code Refactoring**: Decomposed complex methods for maintainability and testing
- **Test Coverage**: 106/106 unit tests + 27/27 integration tests passing

#### **✅ Phase 4.2.2.3.3 Export Coordination with TTL Safety - COMPLETED**
- **TTL-Aware Export Scheduling**: Dynamic scheduling with safety margins preventing data loss
- **Distributed Export Coordination**: Rails.cache atomic operations for cross-container coordination
- **ActiveJob Integration**: Proper Rails job queue patterns with exponential backoff
- **Service Object Pattern**: Clean separation between job coordination and export business logic
- **Sleep Pattern Elimination**: Refactored from blocking sleep calls to asynchronous job retry patterns
- **Comprehensive Architecture**: ExportCoordinator + MetricsExportJob + MetricsExportService
- **Test Coverage**: 36 coordinator + 35 job + 15 service tests = 86 tests passing

#### **🎯 Current Challenge: Plugin Architecture**
Need extensible system for custom export formats while maintaining framework boundaries:
- **Framework Boundary Enforcement**: Tasker provides data, plugins provide integrations
- **Plugin Lifecycle Management**: Registration, validation, execution, error handling
- **Event-Driven Architecture**: Leverage existing event system for plugin triggers
- **Vendor Integration Support**: Enable DataDog, Sentry, custom monitoring system integrations

## 🚀 **Phase 4.2.2.3 Strategic Solution: Hybrid Architecture**

### **Core Strategy: Cache-Agnostic Dual Storage**
Combine performance of in-memory operations with persistence/coordination of Rails.cache:

```ruby
class MetricsBackend
  def initialize
    # Fast thread-safe in-memory storage (preserves current performance)
    @metrics = Concurrent::Hash.new

    # Persistent distributed storage with capability detection
    @cache_capabilities = detect_cache_capabilities
    @sync_strategy = select_sync_strategy  # :distributed_atomic, :distributed_basic, :local_only
  end

  # Fast path: Unchanged concurrent operations for real-time processing
  def counter(name, **labels)
    # Existing logic unchanged - preserves performance
  end

  # Background sync: Periodic cache sync without blocking operations
  def sync_to_cache!
    # Adaptive sync based on Rails.cache capabilities
  end
end
```

### **Design Principles (From docs/OBSERVABILITY_ENHANCEMENT.md)**

1. **Performance Preservation**: Keep `Concurrent::Hash` for hot-path concurrent processing
2. **Cache Store Agnostic**: Feature detection for Redis, Memcached, File, Memory stores
3. **Cross-Container Coordination**: Atomic operations when supported, graceful degradation when not
4. **Framework Boundaries**: Prometheus export (industry standard), plugin architecture for custom formats
5. **TTL Safety**: Export coordination with safety margins prevents data loss

### **Cache Store Compatibility Matrix**
| Cache Store | Distributed | Atomic Ops | Locking | Strategy | Features |
|-------------|-------------|------------|---------|----------|----------|
| `:redis_cache_store` | ✅ | ✅ | ✅ | `distributed_atomic` | Full coordination |
| `:mem_cache_store` | ✅ | ✅ | ❌ | `distributed_basic` | Basic coordination |
| `:file_store` | ❌ | ❌ | ❌ | `local_only` | Local export only |
| `:memory_store` | ❌ | ❌ | ❌ | `local_only` | Single-process only |

## 🛠️ **Implementation Roadmap (5 Days)**

### **✅ Phase 4.2.2.3.1: Cache-Agnostic Feature Detection** (Day 1) - **COMPLETED**
**Focus**: Detect Rails.cache capabilities and select appropriate sync strategy
**Deliverables**:
- ✅ Cache capability detection system
- ✅ Adaptive strategy selection logic
- ✅ Compatibility matrix validation

### **✅ Phase 4.2.2.3.2: Adaptive Sync Implementation** (Day 2) - **COMPLETED**
**Focus**: Multi-strategy sync operations respecting cache limitations
**Deliverables**:
- ✅ Atomic sync for Redis/Memcached
- ✅ Read-modify-write for basic distributed caches
- ✅ Local snapshot for memory/file stores
- ✅ Code refactoring for maintainability

### **✅ Phase 4.2.2.3.3: Export Job Coordination with TTL Safety** (Day 3) - **COMPLETED**
**Focus**: Prevent data loss during cache TTL expiration
**Deliverables**:
- ✅ TTL-coordinated export scheduling with dynamic safety margins
- ✅ Distributed locking for cross-container coordination using Rails.cache atomic operations
- ✅ Emergency TTL extension for failed exports with job execution context awareness
- ✅ Background job integration with ActiveJob retry patterns and service object separation

### **🎯 Phase 4.2.2.3.4: Plugin Architecture for Custom Exporters** (Day 4) - **CURRENT PHASE**
**Focus**: Framework-appropriate extensibility respecting boundaries
**Deliverables**:
- [ ] Export pipeline with plugin system
- [ ] Standard formats (Prometheus, JSON, CSV) - Prometheus already complete
- [ ] Developer-facing custom exporter API
- [ ] Event-driven plugin triggers

### **Phase 4.2.2.3.5: Testing & Integration** (Day 5)
**Focus**: Comprehensive validation and performance testing
**Deliverables**:
- Cache store compatibility testing
- Performance benchmarking
- Cross-container coordination validation

## 🎯 **Framework Boundary Respect**

### **What Tasker Provides (Framework Responsibility)**
- ✅ Thread-safe metrics collection (Counter, Gauge, Histogram)
- ✅ Cache-agnostic coordination (works with any Rails.cache store)
- ✅ Standard export formats (Prometheus, JSON, CSV)
- ✅ Plugin architecture for custom exporters
- ✅ TTL-safe export coordination with automatic recovery

### **What Developers Provide (Application Responsibility)**
- ✅ Vendor integrations (DataDog, Sentry via event subscribers)
- ✅ Custom exporters (for proprietary monitoring systems)
- ✅ Business logic (which metrics to collect, when to alert)
- ✅ Infrastructure choices (Redis vs Memcached vs File cache)

## 📋 **Success Criteria for Phase 4.2.2.3**

### **Functional Requirements**
- ✅ Works with all Rails.cache stores without failure
- ✅ Cross-container metric aggregation when cache supports it
- ✅ Export coordination prevents data loss during TTL expiration
- [ ] Plugin system allows custom export formats

### **Performance Requirements**
- ✅ <5% overhead for in-memory operations (hot path unchanged)
- ✅ Configurable sync frequency (default 30 seconds)
- ✅ Memory-bounded storage with TTL cleanup
- ✅ Export jobs complete within TTL safety margin

### **Framework Compliance**
- [ ] Infrastructure agnostic - no vendor lock-in
- [ ] Standard formats - Prometheus ecosystem compatibility
- [ ] Plugin architecture - developer extensibility
- [ ] Clear boundaries - framework vs application concerns

## 🧠 **Key Architectural Decisions**

### **Decision 1: Preserve In-Memory Performance**
- **Rationale**: Concurrent step processing requires fast metric operations
- **Implementation**: Keep `Concurrent::Hash` for hot-path, sync periodically to cache
- **Benefit**: Zero performance regression for high-throughput scenarios

### **Decision 2: Cache Store Agnostic Design**
- **Rationale**: Rails engine shouldn't assume infrastructure choices
- **Implementation**: Feature detection with graceful degradation
- **Benefit**: Works with any Rails.cache configuration

### **Decision 3: TTL Safety with Export Coordination**
- **Rationale**: Prevent data loss during background job delays
- **Implementation**: Export before TTL expiration with safety margins
- **Benefit**: Reliable metrics persistence in production environments

---

## 🔍 **Technical Approach Review: Phase 4.2.2.3.3 Export Coordination**

### **Problem Statement**
Current cache synchronization creates a race condition where metrics may expire from cache before export jobs complete, leading to permanent data loss. Multiple containers may also attempt simultaneous exports, causing conflicts.

### **Core Technical Challenges**

#### **1. TTL Race Conditions**
- **Issue**: Cache TTL countdown starts at metric creation
- **Risk**: Export jobs may be delayed (queue congestion, resource constraints)
- **Impact**: Metrics expire before export, causing data loss

#### **2. Cross-Container Export Coordination**
- **Issue**: Multiple containers may trigger simultaneous exports
- **Risk**: Duplicate/conflicting export operations
- **Impact**: Resource waste, potential data corruption

#### **3. Background Job Integration**
- **Issue**: Need to integrate with existing Rails job system
- **Risk**: Job failures, retries, queue delays
- **Impact**: Unreliable export execution

### **Proposed Technical Solutions**

#### **Solution 1: TTL-Aware Export Scheduling**
```ruby
class ExportCoordinator
  def schedule_export(safety_margin: 1.minute)
    next_export_time = calculate_next_export_time
    ttl_expiry = calculate_cache_ttl_expiry

    # Ensure export completes before TTL expiry
    if next_export_time + safety_margin > ttl_expiry
      extend_cache_ttl(ttl_expiry + safety_margin)
    end

    ExportJob.set(wait_until: next_export_time).perform_later
  end
end
```

#### **Solution 2: Distributed Locking**
```ruby
class DistributedExportLock
  def with_export_lock(timeout: 5.minutes)
    lock_key = "tasker:metrics:export_lock"

    # Try to acquire distributed lock
    if Rails.cache.write(lock_key, instance_id,
                        expires_in: timeout,
                        unless_exist: true)
      begin
        yield  # Execute export
      ensure
        Rails.cache.delete(lock_key)
      end
    else
      # Another container is already exporting
      Rails.logger.info "Export already in progress by another container"
    end
  end
end
```

#### **Solution 3: Export Recovery Mechanisms**
```ruby
class ExportRecovery
  def extend_ttl_for_failed_export(metric_keys, extension_time: 5.minutes)
    metric_keys.each do |key|
      current_data = Rails.cache.read(key)
      next unless current_data

      # Extend TTL to prevent data loss
      Rails.cache.write(key, current_data,
                       expires_in: @retention_window + extension_time)
    end

    Rails.logger.warn "Extended TTL for #{metric_keys.size} metrics due to export failure"
  end
end
```

### **Integration Points**

#### **Rails Job System Integration**
- **Approach**: Create dedicated `MetricsExportJob` class
- **Benefits**: Leverages existing job infrastructure, retry mechanisms, monitoring
- **Considerations**: Queue prioritization, error handling, monitoring

#### **Cache Store Compatibility**
- **Redis/Memcached**: Full distributed locking support with atomic operations
- **Memory/File**: Local-only mode with simplified coordination
- **Auto-detection**: Use existing cache capability detection system

#### **Monitoring & Observability**
- **Export Success/Failure Metrics**: Track export reliability
- **TTL Extension Events**: Monitor when emergency extensions occur
- **Lock Acquisition Stats**: Understand cross-container coordination patterns

### **✅ Technical Decisions CONFIRMED**

#### **✅ Decision 1: Dynamic TTL-Aware Scheduling**
**Chosen Approach**: Dynamic export timing based on cache TTL with safety margins
- **Benefits**: Production efficiency, prevents data loss, optimal resource usage
- **Implementation**: Calculate next export time relative to cache expiration

#### **✅ Decision 2: Rails.cache Atomic Operations with Graceful Degradation**
**Chosen Approach**: Use cache store's native locking with capability detection
- **Redis/Memcached**: Full atomic locking via `Rails.cache.write(unless_exist: true)`
- **SolidCache**: DB-level locking for free (excellent for Rails-backed cache)
- **Memory/File**: Documented limitations with smart defaults
- **Benefits**: Cache-store agnostic, clear capability communication

#### **✅ Decision 3: TTL Extension + Configurable Retry Limits**
**Chosen Approach**: Extend cache TTL when exports fail, retry with limits
- **Configurable Limits**: Prevent infinite retry loops
- **Data Preservation**: Prioritize data integrity over speed
- **Benefits**: Reliable export completion, configurable resilience

#### **✅ Decision 4: Job Runner Architecture Pattern**
**Key Insight**: Separate concerns between web containers and job runners
- **Web Containers**: Handle real-time metrics collection (hot path performance)
- **Job Runner Pods**: Dedicated export aggregation without affecting requests
- **Point-in-Time Aggregation**: Export job creates snapshot, no global coordination
- **Benefits**: Clean separation of concerns, better resource utilization

#### **✅ Decision 5: Rails ActiveJob Integration**
**Chosen Approach**: Use Rails ActiveJob for any backend compatibility
- **Supports**: Sidekiq, SQS, SolidJob, DelayedJob, etc.
- **Benefits**: Framework agnostic, leverages existing infrastructure

#### **✅ Decision 6: Real Integration Testing**
**Approach**: Test against actual Jaeger/Prometheus Docker instances
- **Jaeger**: HTTP OTLP endpoint + Query API validation
- **Prometheus**: Remote Write + Query API validation
- **Non-failing**: Missing endpoints don't break tests (like OpenTelemetry pattern)
- **Curl Validation**: Verify actual data export end-to-end

---

## **🎯 REFINED IMPLEMENTATION FOCUS**

### **Production-Ready Architecture Benefits**
1. **Resource Efficiency**: Job runners handle aggregation, web containers stay fast
2. **Cache Store Flexibility**: Works optimally with any Rails.cache backend
3. **Data Reliability**: TTL coordination prevents data loss with configurable limits
4. **Real-World Validation**: Integration tests against actual monitoring services
5. **Framework Agnostic**: Uses Rails patterns, works with any job backend

### **Next Steps**
- Implement ExportCoordinator with dynamic TTL scheduling
- Build DistributedExportLock with capability-aware locking
- Create MetricsExportJob with ActiveJob integration
- Add Prometheus configuration following OpenTelemetry pattern
- Build integration tests with curl validation against Docker services

**READY FOR IMPLEMENTATION**: Begin Phase 4.2.2.3.4 Plugin Architecture for Custom Exporters
