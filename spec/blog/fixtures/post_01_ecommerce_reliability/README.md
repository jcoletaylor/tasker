# E-commerce Order Processing - Complete Code Example

This directory contains a complete, runnable example of the e-commerce order processing workflow described in the blog post.

## Structure

```
code-examples/
├── task_handler/
│   └── order_processing_handler.rb     # Main workflow definition
├── step_handlers/
│   ├── validate_cart_handler.rb        # Cart validation step
│   ├── process_payment_handler.rb      # Payment processing step
│   ├── update_inventory_handler.rb     # Inventory management step
│   ├── create_order_handler.rb         # Order creation step
│   └── send_confirmation_handler.rb    # Email confirmation step
├── config/
│   └── order_processing.yaml           # YAML workflow configuration
├── models/
│   ├── product.rb                      # Product model for demo
│   └── order.rb                        # Order model for demo
└── demo/
    ├── checkout_controller.rb          # Demo controller
    ├── payment_simulator.rb            # Simulated payment processor
    └── sample_data.rb                  # Sample products and test data
```

## Key Features Demonstrated

1. **Atomic Step Design**: Each step is independent and retryable
2. **Dependency Management**: Steps execute in correct order
3. **Error Handling**: Different retry strategies for different step types
4. **State Management**: Complete visibility into workflow progress
5. **Type Safety**: JSON schema validation for inputs

## Running the Example

See the setup scripts in `../setup-scripts/` for complete installation instructions.

## Code Highlights

### Workflow Definition Pattern
The main workflow handler defines the step sequence and dependencies using Tasker's declarative DSL.

### Step Handler Pattern
Each step handler implements a single responsibility with clear input/output contracts.

### Error Handling Strategy
- Payment steps: Retry 3 times with exponential backoff
- Inventory steps: Retry 2 times (may require manual intervention)
- Email steps: Retry 5 times (delivery can be very flaky)

### State Recovery
If any step fails, the workflow can be resumed from the exact failure point without re-executing successful steps.
