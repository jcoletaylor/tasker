# Chapter 3: Code Examples

This directory contains the complete microservices coordination implementation.

## 📁 Directory Structure

```
code-examples/
├── config/               # YAML task configurations
│   └── user_registration_handler.yaml
├── task_handler/        # Main task orchestration
│   └── user_registration_handler.rb
└── step_handlers/       # Service-specific handlers
    ├── api_base_handler.rb
    ├── create_user_account_handler.rb
    ├── setup_billing_profile_handler.rb
    ├── initialize_preferences_handler.rb
    ├── send_welcome_sequence_handler.rb
    ├── update_user_status_handler.rb
    └── CIRCUIT_BREAKER_EXPLANATION.md
```

## 🌟 Key Concepts Demonstrated

### 1. **Enhanced API Base Handler**
The `api_base_handler.rb` extends `Tasker::StepHandler::Api` with:
- Correlation ID tracking for distributed debugging
- Enhanced error classification using `RetryableError` vs `PermanentError`
- Structured logging for microservices observability

### 2. **Service-Specific Step Handlers**
Each handler demonstrates:
- **Idempotent operations** - Safe to retry without side effects
- **Graceful degradation** - Services can fail without breaking the workflow
- **Proper error classification** - Permanent vs transient failures

### 3. **Circuit Breaker Architecture**
Instead of custom circuit breakers, we leverage Tasker's native capabilities:
- **SQL-driven retry state** - Persistent across process restarts
- **Distributed coordination** - Multiple workers respect the same backoff
- **Intelligent backoff** - Exponential with jitter and server-suggested delays

## 📖 Files Overview

### Configuration
- **`user_registration_handler.yaml`** - Defines workflow structure, dependencies, and retry policies

### Task Handler
- **`user_registration_handler.rb`** - Runtime customization and correlation ID generation

### Step Handlers
- **`create_user_account_handler.rb`** - Creates user with idempotency checks
- **`setup_billing_profile_handler.rb`** - Billing setup with graceful degradation for free plans
- **`initialize_preferences_handler.rb`** - Preferences with fallback defaults
- **`send_welcome_sequence_handler.rb`** - Welcome emails with rate limit handling
- **`update_user_status_handler.rb`** - Final status update with distributed state tracking

### Documentation
- **`CIRCUIT_BREAKER_EXPLANATION.md`** - Why Tasker's approach beats custom implementations

## 💡 Usage Example

```ruby
# Trigger the workflow
task = UserManagement::UserRegistrationHandler.create(
  email: 'sarah@growthcorp.com',
  name: 'Sarah Chen',
  plan: 'pro',
  marketing_consent: true
)

# Monitor progress
task.reload
puts "Status: #{task.status}"
puts "Failed steps: #{task.failed_steps.map(&:name)}"
puts "Correlation ID: #{task.annotations['correlation_id']}"
```

## 🔍 Key Learning

The most important lesson: **Don't re-implement what your framework already provides better**. Tasker's SQL-driven retry architecture provides superior circuit breaker functionality compared to in-memory implementations.