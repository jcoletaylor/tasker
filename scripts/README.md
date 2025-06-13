# Tasker Debug Scripts

This directory contains debug scripts that were instrumental in diagnosing and fixing critical issues during the SQL function optimization work. These scripts are preserved for future debugging and development reference.

## Scripts Overview

### `debug_backoff_logic.rb` - ✅ **CRITICAL PRODUCTION FIX**
**Purpose**: Test and validate SQL function backoff timing logic
**Historical Significance**: This script discovered a critical production bug where steps in active backoff were incorrectly marked as ready for execution, potentially causing race conditions and duplicate processing.

**Usage**:
```bash
cd /path/to/tasker
RAILS_ENV=test bundle exec rails runner scripts/debug_backoff_logic.rb
```

**What it tests**:
- Creates a task with two independent steps
- Sets one step to backoff (30 seconds)
- Verifies SQL function correctly excludes backoff steps from execution
- Validates that non-backoff steps remain ready

**Critical Bug Fixed**: The original SQL function used incorrect OR logic that would return `true` when backoff was active. This script helped identify and validate the fix using proper CASE statement logic.

### `debug_sql_functions.rb` - 🔧 **COMPREHENSIVE SQL FUNCTION DEBUGGER**
**Purpose**: Comprehensive debugging of SQL function behavior and integration
**Value**: Provides detailed analysis of SQL function results vs Ruby model behavior

**Usage**:
```bash
cd /path/to/tasker
RAILS_ENV=test bundle exec rails runner scripts/debug_sql_functions.rb
```

**What it analyzes**:
- Task and step creation via factories
- Step state transitions and dependencies
- SQL function results vs Ruby model results
- Task execution context analysis
- TaskFinalizer integration testing

**Use Cases**:
- Debugging SQL function accuracy
- Comparing SQL vs Ruby model results
- Investigating step readiness calculation issues
- Validating task execution context generation

### `debug_workflow_execution.rb` - 🔍 **WORKFLOW EXECUTION ANALYZER**
**Purpose**: Debug workflow execution issues and step processing
**Value**: Comprehensive analysis of workflow execution pipeline

**Usage**:
```bash
cd /path/to/tasker
bundle exec ruby scripts/debug_workflow_execution.rb
```

**What it analyzes**:
- Task creation and step initialization
- SQL function step readiness results
- Task execution context generation
- Viable steps identification via WorkflowStep.get_viable_steps
- Complete workflow execution pipeline

**Use Cases**:
- Debugging workflow execution failures
- Investigating step readiness issues
- Validating task handler integration
- Analyzing workflow step dependencies

## Historical Context

These scripts were created during the **SQL Function Optimization Phase** (June 2025) when migrating from database views to high-performance SQL functions. They played crucial roles in:

1. **Discovering Critical Bugs**: `debug_backoff_logic.rb` identified a production-critical backoff timing bug
2. **Validating Performance**: Scripts confirmed 4x performance improvements over database views
3. **Ensuring Correctness**: Comprehensive testing revealed and helped fix workflow execution issues

## Development Guidelines

### When to Use These Scripts
- **SQL Function Changes**: Run `debug_sql_functions.rb` after modifying SQL functions
- **Backoff Logic Changes**: Always run `debug_backoff_logic.rb` after backoff-related changes
- **Workflow Issues**: Use `debug_workflow_execution.rb` for workflow execution problems

### Adding New Debug Scripts
When adding new debug scripts to this directory:
1. Use descriptive names: `debug_[specific_feature].rb`
2. Include comprehensive output with clear section headers
3. Add error handling for graceful failure analysis
4. Document the script's purpose in this README
5. Include usage examples and expected output

### Converting to Tests
Consider converting debug scripts to permanent tests when:
- They validate critical correctness logic (like backoff timing)
- They test complex integration scenarios
- They prevent regression of fixed bugs
- They validate performance characteristics

## Maintenance Notes

- **Keep Updated**: Update scripts when underlying models or SQL functions change
- **Document Changes**: Update this README when adding or modifying scripts
- **Test Regularly**: Run scripts periodically to catch regressions early
- **Archive Obsolete**: Move outdated scripts to `scripts/archive/` with documentation

## Related Documentation

- `docs/TASKER_DATABASE_PERFORMANCE_COMPREHENSIVE_GUIDE.md` - Complete SQL function optimization guide
- `spec/db/functions/sql_functions_integration_spec.rb` - Formal SQL function tests
- `spec/integration/workflow_testing_infrastructure_demo_spec.rb` - Workflow testing infrastructure

---

**Note**: These scripts require a properly configured test environment with FactoryBot and all Tasker dependencies loaded.
