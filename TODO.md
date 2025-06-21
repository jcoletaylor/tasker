# Tasker Development TODO

## 🎯 CURRENT PRIORITY: Phase 3.x.2 REST API Endpoints Enhancement

**Status**: **Phase 3.x.1 COMPLETE** ✅ - Database foundation and HandlerFactory architecture successfully implemented

### ✅ **PHASE 3.x.1 COMPLETED - Database Foundation**
- **TaskNamespace Model**: ✅ Complete with robust default handling
- **NamedTask Enhancement**: ✅ Full namespace + version + configuration support
- **HandlerFactory 3-Level Registry**: ✅ namespace → name → version architecture
- **TaskBuilder Integration**: ✅ YAML configs support namespace_name + version
- **Plugin Integration**: ✅ All lookups use proper namespace + version
- **GraphQL Enhancement**: ✅ APIs support namespace + version parameters
- **Test Coverage**: ✅ Comprehensive testing and factory compatibility
- **Migration Success**: ✅ All database changes applied successfully

---

## 🏗️ PHASE 3.x.2: REST API Endpoints Enhancement (CURRENT FOCUS)

### Sprint 1: Task Management API Enhancement 🚨 IMMEDIATE
**Objective**: Update REST API controllers to support namespace + version parameters

#### **Task Creation Endpoints**
- [ ] **TasksController#create**: Add namespace + version parameter support
- [ ] **Task Request Validation**: Validate namespace + version inputs
- [ ] **Error Handling**: Proper error responses for invalid namespace/version
- [ ] **Default Handling**: Graceful fallback to default namespace + version

#### **Task Status & Query Endpoints**
- [ ] **TasksController#show**: Include namespace + version in responses
- [ ] **TasksController#index**: Add namespace filtering capabilities
- [ ] **Task Status API**: Enhanced responses with full task identification
- [ ] **Query Performance**: Optimize namespace-scoped queries

#### **Handler Management API**
- [ ] **HandlersController**: New controller for handler management
- [ ] **GET /handlers**: List all handlers with namespace filtering
- [ ] **GET /handlers/:namespace**: List handlers in specific namespace
- [ ] **GET /handlers/:namespace/:name**: List versions of specific handler
- [ ] **GET /namespaces**: Enumerate all registered namespaces

### Sprint 2: Enhanced API Features
**Objective**: Advanced namespace and version management capabilities

#### **Version Negotiation**
- [ ] **Version Resolution**: Implement "latest" version resolution
- [ ] **Version Compatibility**: Add version compatibility checking
- [ ] **API Versioning**: Consider API endpoint versioning strategy

#### **Namespace Administration**
- [ ] **Namespace Management**: CRUD operations for TaskNamespace
- [ ] **Namespace Validation**: Prevent deletion of namespaces with active tasks
- [ ] **Namespace Statistics**: Usage metrics and task counts per namespace

---

## 🏗️ PHASE 3.x.3: Runtime Dependency Graph API (PLANNED)

### Sprint 3: Graph Analysis & Visualization
**Objective**: Expose runtime dependency analysis through API endpoints

#### **Template Graph API**
- [ ] **GET /templates/:namespace/:name/:version/graph**: Template dependency visualization
- [ ] **Template Analysis**: Cycle detection, topological ordering
- [ ] **Template Validation**: Pre-runtime dependency validation

#### **Runtime Graph API**
- [ ] **GET /tasks/:id/graph**: Live task execution graph
- [ ] **Step Dependencies**: Real-time dependency status
- [ ] **Graph Metrics**: Execution progress, bottleneck analysis

---

## 🏗️ PHASE 3.x.4: Template Management Interface (PLANNED)

### Sprint 4: Template Administration
**Objective**: Management interface for task templates and configurations

#### **Template Management**
- [ ] **Template CRUD**: Create, update, delete task templates
- [ ] **Configuration Management**: YAML template editing interface
- [ ] **Version Management**: Template versioning and migration tools

---

## 📋 IMPLEMENTATION NOTES

### **Key Architectural Decisions from Phase 3.x.1**

#### **1. TaskNamespace vs dependent_system Separation** ✅
- **TaskNamespace**: Organizational hierarchy (`payments`, `inventory`, `notifications`)
- **dependent_system**: External integration context (preserved in step templates)
- **Result**: Clean separation of organizational vs. integration concerns

#### **2. 3-Level HandlerFactory Registry** ✅
```ruby
# Registry Structure: namespace_name → handler_name → version → handler_class
handler_classes[:payments][:process_order]['1.0.0'] = PaymentHandler
handler_classes[:inventory][:process_order]['2.1.0'] = InventoryHandler

# Method Signatures
register(name, class_name, namespace_name: :default, version: '0.1.0')
get(name, namespace_name: :default, version: '0.1.0')
```

#### **3. Robust Default Handling** ✅
- **TaskNamespace.default**: Always works via find_or_create_by (no seeding required)
- **Default Values**: namespace='default', version='0.1.0' for all unspecified
- **Backward Compatibility**: Existing code continues working unchanged

#### **4. Full Integration Chain** ✅
```ruby
# Complete integration: NamedTask → HandlerFactory → Task Creation
NamedTask.find_or_create_by_full_name!(
  namespace_name: 'payments', name: 'process_order', version: '1.0.0'
)

handler_factory.get(
  task.name,
  namespace_name: task.named_task.task_namespace.name,
  version: task.named_task.version
)
```

### **Success Validation**
- ✅ **Zero Breaking Changes**: All existing handlers work with defaults
- ✅ **Test Coverage**: Comprehensive model, integration, and factory tests
- ✅ **Performance**: Registry lookup remains O(1) with hash access
- ✅ **Architecture**: Clean separation of concerns achieved
- ✅ **Database**: Migrations successful, associations working
- ✅ **Integration**: All components work together seamlessly

---

## 🎯 NEXT IMMEDIATE ACTIONS

**Priority 1**: Begin Phase 3.x.2 REST API enhancement
1. Update TasksController#create for namespace + version support
2. Add namespace parameter validation
3. Implement proper error handling for invalid namespace/version
4. Add comprehensive API tests for new functionality

**Priority 2**: Create HandlersController for handler management API
1. Implement handler listing with namespace filtering
2. Add namespace enumeration endpoint
3. Create version-aware handler lookup endpoints

**Priority 3**: Update API documentation and examples
1. Document new namespace + version parameters
2. Update API examples with namespace usage
3. Create migration guide for existing API consumers

**Status**: **Ready to begin Phase 3.x.2 REST API endpoint enhancement**
