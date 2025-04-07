# Tasker Task Handler Generator

## Description

The task_handler generator creates a new Tasker task handler with the necessary configuration files, step handlers, and specs. It sets up the structure for implementing a Tasker workflow based on a YAML configuration.

The generator uses the directory structure configured in `Tasker.configuration`. Default directories are 'tasks' for both handler and config files.

## Usage

```bash
rails generate task_handler OrderProcess
```

## Generated Files

This will create (using configured directories):

- `config/[task_config_directory]/order_process.yaml` - Task configuration
- `app/[task_handler_directory]/order_process.rb` - Task handler class
- `app/[task_handler_directory]/order_process_step_handler.rb` - Step handler implementation
- `spec/[task_handler_directory]/order_process_spec.rb` - Test file

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--module-namespace=NAMESPACE` | The module namespace for the task handler | OurTask |
| `--concurrent=true\|false` | Whether the task can be run concurrently | true |
| `--dependent-system=SYSTEM` | The default dependent system for the task | default_system |

## Example

```bash
# Generate with custom options
rails generate task_handler PaymentProcess --module-namespace=Payment --dependent-system=payment_system --concurrent=false
```
