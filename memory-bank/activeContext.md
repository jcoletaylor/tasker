# Active Context: Phase 4.2.2.3 Hybrid Rails Cache + Event-Driven Export Architecture

## 🎯 Current Focus: Cache-Agnostic Metrics Architecture Implementation

**Current State**: **Phase 4.2.2.2 Prometheus Export Integration COMPLETED** with production-ready metrics endpoint
**Next Target**: **Phase 4.2.2.3 Hybrid Rails Cache + Event-Driven Export Architecture** - Cache-agnostic dual-storage system

**📋 COMPREHENSIVE PLAN**: See `docs/OBSERVABILITY_ENHANCEMENT.md` Section 4.2.2.3 for complete architectural details, implementation timeline, and technical specifications.

### 📍 **Where We Are Right Now**

#### **✅ Phase 4.2.2.2 Just Completed**
- **Production-Ready Metrics System**: Complete MetricsBackend with thread-safe Counter, Gauge, Histogram
- **Prometheus Export Integration**: Standard format conversion with `/tasker/metrics` endpoint
- **Optional Authentication**: Configurable security with granular permissions
- **EventRouter Foundation**: Intelligent event routing with declarative configuration
- **1298 Tests Passing**: Only 6 authorization test failures (system fully functional)

#### **🚨 Critical Production Limitation Identified**
Current `Concurrent::Hash` in-memory storage has fundamental issues for production:
- **Memory Accumulation**: Indefinite growth in long-running containers → OOM kills
- **Data Loss**: Container recycling loses all metrics
- **Cross-Container Isolation**: No coordination across distributed instances
- **Resource Waste**: Memory grows linearly with metric events

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

### **Phase 4.2.2.3.1: Cache-Agnostic Feature Detection** (Day 1)
**Focus**: Detect Rails.cache capabilities and select appropriate sync strategy
**Deliverables**:
- Cache capability detection system
- Adaptive strategy selection logic
- Compatibility matrix validation

### **Phase 4.2.2.3.2: Adaptive Sync Implementation** (Day 2)
**Focus**: Multi-strategy sync operations respecting cache limitations
**Deliverables**:
- Atomic sync for Redis/Memcached
- Read-modify-write for basic distributed caches
- Local snapshot for memory/file stores

### **Phase 4.2.2.3.3: Export Job Coordination with TTL Safety** (Day 3)
**Focus**: Prevent data loss during cache TTL expiration
**Deliverables**:
- TTL-coordinated export scheduling
- Distributed locking for cross-container coordination
- Emergency TTL extension for failed exports

### **Phase 4.2.2.3.4: Plugin Architecture for Custom Exporters** (Day 4)
**Focus**: Framework-appropriate extensibility respecting boundaries
**Deliverables**:
- Export pipeline with plugin system
- Standard formats (Prometheus, JSON, CSV)
- Developer-facing custom exporter API

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
- [ ] Works with all Rails.cache stores without failure
- [ ] Cross-container metric aggregation when cache supports it
- [ ] Export coordination prevents data loss during TTL expiration
- [ ] Plugin system allows custom export formats

### **Performance Requirements**
- [ ] <5% overhead for in-memory operations (hot path unchanged)
- [ ] Configurable sync frequency (default 30 seconds)
- [ ] Memory-bounded storage with TTL cleanup
- [ ] Export jobs complete within TTL safety margin

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

**Next Action**: Begin Phase 4.2.2.3.1 implementation following detailed plan in `docs/OBSERVABILITY_ENHANCEMENT.md`
