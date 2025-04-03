# YAML-based Task Handlers

## Overview

Tasker now supports defining task handlers using YAML files. This approach allows for a more declarative way to define task handlers, reducing the need for boilerplate Ruby code and making configuration more explicit and maintainable.

## YAML Structure

A YAML task handler configuration consists of the following sections:

```yaml
---
name: task_name                    # Name for registering with the handler factory
module_namespace: ModuleName       # Module where the class will be defined
class_name: ClassName              # Class name for the handler
concurrent: true                   # Whether to enable concurrent processing

default_dependent_system: system_name  # Default system name for all steps (can be overridden in step templates)

named_steps:                       # List of step names for validation and constant generation
  - step_one
  - step_two
  - step_three

schema:                            # JSON schema for validating task context
  type: object
  required:
    - required_field
  properties:
    required_field:
      type: integer

step_templates:                    # Array of step templates
  - name: step_one                 # Must match a name in named_steps
    description: Step description
    handler_class: Module::StepHandlerClass
    # dependent_system is optional if default_dependent_system is specified
    dependent_system: override_system_name  # Override the default system
    handler_config:                # Optional configuration for the step handler
      type: api
      url: https://api.example.com
      params:
        param1: value1
    # Dependencies (must reference steps in named_steps)
    depends_on_step: step_two       # Single dependency
    depends_on_steps:               # Multiple dependencies
      - step_two
      - step_three
    # Additional configuration
    default_retryable: true
    default_retry_limit: 3
    skippable: false
```

## Automatic Constant Generation

The TaskBuilder automatically generates constants for each task handler based on the YAML configuration:

1. **NAMED_STEPS Constant**: A single constant `NAMED_STEPS` is created containing all the step names defined in the `named_steps` section.
   * This allows you to reference step names in your code: `YourHandler::NAMED_STEPS`.

2. **DEFAULT_DEPENDENT_SYSTEM**: If specified, a `DEFAULT_DEPENDENT_SYSTEM` constant is created with the value from the YAML.

This automatic constant generation removes the need for manually defining constants in the task handler class and ensures consistency between step names in the configuration and code.

To reference individual steps, you can access them through the `NAMED_STEPS` array, e.g. `YourHandler::NAMED_STEPS[0]` or use the step name directly in method calls.

## Step Name Validation

The TaskBuilder validates that:
- All step names in `step_templates` exist in the `named_steps` list
- All dependency steps (in `depends_on_step` or `depends_on_steps`) exist in the `named_steps` list

This ensures consistency and catches configuration errors early.

## Usage

### Creating a YAML Task Handler

1. Create a YAML file defining your task handler following the structure above
2. Place it in an appropriate directory, e.g., `app/task_handlers/your_task_handler.yaml`

## Example of creating a YAML-configured task handler

```ruby
module MyModule
  class MyYamlTask < Tasker::ConfiguredTask
    def self.yaml_path
      Rails.root.join('config/tasks/my_task.yaml')
    end
  end
end

# Usage:
handler = MyModule::MyYamlTask.new
# The class is already built and ready to use
```

## Example

Here's an example YAML file for an e-commerce API integration task handler:

```yaml
---
name: api_integration_yaml_task
module_namespace: ApiTask
class_name: IntegrationYamlExample
concurrent: true

default_dependent_system: ecommerce_system

named_steps:
  - fetch_cart
  - fetch_products
  - validate_products
  - create_order
  - publish_event

schema:
  type: object
  required:
    - cart_id
  properties:
    cart_id:
      type: integer

step_templates:
  - name: fetch_cart
    description: Fetch cart details from e-commerce system
    handler_class: ApiTask::StepHandler::CartFetchStepHandler
    handler_config:
      type: api
      url: https://api.ecommerce.com/cart
      params:
        cart_id: 1

  - name: fetch_products
    description: Fetch product details from product catalog
    handler_class: ApiTask::StepHandler::ProductsFetchStepHandler
    handler_config:
      type: api
      url: https://api.ecommerce.com/products

  - name: validate_products
    description: Validate product availability
    depends_on_steps:
      - fetch_products
      - fetch_cart
    handler_class: ApiTask::StepHandler::ProductsValidateStepHandler

  - name: create_order
    description: Create order from validated cart
    depends_on_step: validate_products
    handler_class: ApiTask::StepHandler::CreateOrderStepHandler

  - name: publish_event
    description: Publish order created event
    depends_on_step: create_order
    handler_class: ApiTask::StepHandler::PublishEventStepHandler
```

## Benefits

- **Declarative**: Configuration is explicit and separated from implementation
- **Maintainable**: Easier to review and modify task handler structure
- **Consistent**: Standardized format for all task handlers
- **Validated**: Configuration is validated against a schema
- **Centralized**: Common patterns are handled by the TaskBuilder
- **DRY**: Default dependent system and constants are set once and reused
- **Auto-generated**: The NAMED_STEPS constant is automatically created from the named_steps list
- **Extensible**: Implementing classes can add additional constants if needed
