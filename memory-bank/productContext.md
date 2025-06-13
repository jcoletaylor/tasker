# Product Context

## Why Tasker Exists

### The Problem
Enterprise applications often need to execute complex, multi-step workflows that involve:
- **Dependencies between steps**: Step B can't run until Step A completes
- **Failure recovery**: When Step C fails, the system needs intelligent retry logic
- **State persistence**: Workflows must survive application restarts and failures
- **Observability**: Teams need visibility into workflow execution and bottlenecks
- **Scale**: Handle thousands of concurrent workflows efficiently

### Traditional Solutions Fall Short
- **Simple job queues**: Don't handle dependencies or complex retry logic
- **Workflow engines**: Often heavyweight, complex to integrate, or vendor-locked
- **Custom solutions**: Brittle, hard to test, and difficult to maintain

### Tasker's Solution
Tasker provides a **Ruby-native workflow orchestration system** that integrates seamlessly with Rails applications while providing enterprise-grade reliability and performance.

## How Tasker Works

### Core Concepts
1. **Tasks**: High-level workflow instances (e.g., "Process Order #12345")
2. **Steps**: Individual units of work within a task (e.g., "Validate Payment", "Update Inventory")
3. **Dependencies**: DAG-based relationships between steps
4. **State Machines**: Robust state management for both tasks and steps
5. **Handlers**: Ruby classes that define step logic and dependencies

### Key Workflows

#### Workflow Definition
```ruby
class OrderProcessingTask
  include Tasker::TaskHandler

  define_step_templates do |templates|
    templates.define(name: 'validate_payment', depends_on_step: nil)
    templates.define(name: 'update_inventory', depends_on_step: 'validate_payment')
    templates.define(name: 'send_confirmation', depends_on_step: 'update_inventory')
  end
end
```

#### Workflow Execution
1. **Step Discovery**: SQL functions identify which steps are ready to execute
2. **Concurrent Execution**: Ready steps execute in parallel when possible
3. **State Transitions**: Steps transition through pending → in_progress → complete/error
4. **Retry Logic**: Failed steps are retried with exponential backoff
5. **Task Finalization**: Tasks complete when all steps are done

#### Failure Recovery
- **Automatic Retries**: Configurable retry limits with exponential backoff
- **Manual Recovery**: Failed workflows can be manually restarted
- **Partial Completion**: Completed steps don't re-execute on retry

## User Experience Goals

### For Developers
- **Simple Integration**: Include gem, define handlers, execute workflows
- **Powerful Testing**: Rich test infrastructure for complex scenarios
- **Clear Debugging**: Comprehensive logging and event system
- **Performance**: Sub-second step readiness calculations even with thousands of steps

### For Operations Teams
- **Observability**: Real-time workflow monitoring and metrics
- **Reliability**: Workflows survive database failures and application restarts
- **Scalability**: Handle high-volume workflow execution efficiently
- **Maintainability**: Clear separation of concerns and well-documented APIs

### For Business Users
- **Consistency**: Workflows execute reliably and predictably
- **Transparency**: Clear visibility into workflow progress and failures
- **Recovery**: Failed processes can be diagnosed and restarted
- **Audit Trail**: Complete history of workflow execution for compliance

## Success Metrics
- **Reliability**: 99.9%+ workflow completion rate
- **Performance**: <100ms step readiness calculation for 1000+ step workflows
- **Developer Experience**: <1 hour to implement and test a new workflow
- **Operational Excellence**: <5 minutes to diagnose and recover from workflow failures
