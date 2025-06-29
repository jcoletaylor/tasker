# Tasker Application Template Generator

The Tasker Application Template Generator provides a one-line creation experience for building production-ready applications that leverage Tasker's enterprise workflow orchestration capabilities. Version 2.6.0 introduces Docker-based development environments and comprehensive dry-run validation.

## Quick Start

### One-Line Creation (Interactive)
```bash
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/scripts/install-tasker-app.sh | bash
```

This will:
1. Check your system dependencies (Ruby 3.0+, Rails 7+, Git)
2. Download the application generator and templates
3. Run an interactive setup to customize your application
4. Create a complete Rails application with Tasker integration

### Docker-Based Development (NEW in v2.6.0)
```bash
# Create a Docker-based development environment
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/scripts/install-tasker-app.sh | bash -s -- \
  --app-name my-tasker-app \
  --docker \
  --with-observability
```

This creates a complete Docker environment with:
- Rails application container with live code reloading
- PostgreSQL 15 with Tasker schema
- Redis 7 for caching and background jobs
- Jaeger distributed tracing (optional)
- Prometheus metrics collection (optional)

### Non-Interactive Creation
```bash
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/scripts/install-tasker-app.sh | bash -s -- \
  --app-name my-tasker-app \
  --tasks ecommerce,inventory \
  --non-interactive
```

### With Custom Options
```bash
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/scripts/install-tasker-app.sh | bash -s -- \
  --app-name ecommerce-app \
  --tasks ecommerce \
  --output-dir ./my-applications \
  --no-observability
```

## Available Options

| Option | Description | Default |
|--------|-------------|---------|
| `--app-name NAME` | Name of the Tasker application | `my-tasker-app` |
| `--tasks LIST` | Comma-separated application templates to include | `ecommerce,inventory,customer` |
| `--output-dir DIR` | Where to create the application | `./tasker-applications` |
| `--observability` | Include OpenTelemetry/Prometheus config | `true` |
| `--interactive` | Enable interactive prompts | `true` |
| `--api-base-url URL` | DummyJSON API base URL | `https://dummyjson.com` |
| `--docker` | Generate Docker-based development environment | `false` |
| `--with-observability` | Include Jaeger and Prometheus in Docker setup | `false` |

## What Gets Created

The generator creates a complete Rails application featuring:

### 🏗️ **Application Structure**
- Rails 7+ API application with Tasker integration
- Proper Gemfile with Tasker gem and dependencies
- Database setup with Tasker migrations
- Development and production configurations

### 📋 **Application Templates**
Choose from three business domains:

**E-commerce (`ecommerce`)**
- Order processing workflow
- Cart validation → Inventory check → Pricing calculation → Order creation
- DummyJSON API integration for realistic data

**Inventory Management (`inventory`)**
- Stock monitoring and reorder management
- Threshold-based stock level monitoring
- Low stock identification and alerting

**Customer Onboarding (`customer`)**
- User registration and validation workflow
- Duplicate user detection
- Registration data validation

### 🎨 **Generated Components**

**YAML Configuration Files** (`config/tasker/tasks/`)
- Proper `Tasker::ConfiguredTask` format
- Environment-specific configurations
- Step templates with dependencies

**Step Handler Classes** (`app/tasks/`)
- API integration handlers using `Tasker::StepHandler::Api`
- Calculation handlers for business logic
- Database operation handlers
- Notification handlers (email, SMS, webhooks, Slack)

**Enhanced Configuration** (`config/initializers/tasker.rb`)
- Authentication setup
- Telemetry and metrics configuration
- Engine configuration with proper directories
- Health check configuration

### 📊 **Observability Stack**
- OpenTelemetry integration for distributed tracing
- Prometheus metrics collection
- Structured logging with correlation IDs
- Example configurations for Jaeger, Zipkin, and other OTLP backends

### 📚 **Documentation**
- Comprehensive README with setup instructions
- API endpoint documentation
- Example GraphQL queries and REST API calls
- Observability setup guides

## Architecture Benefits

### 🔄 **Two-Layer Approach**
1. **Shell Script Layer**: Environment validation, dependency checking, file downloads
2. **Ruby Script Layer**: Complex application generation, template processing, Rails integration

### ✨ **Why This Pattern Works**
- **Familiar**: Developers expect `curl | sh` for dev tools
- **Robust**: Ruby script provides comprehensive environment validation
- **Maintainable**: Complex logic stays in Ruby where it belongs
- **Flexible**: Easy to extend with new task types and configurations
- **Marketing**: Reduces friction for trying Tasker

## Security Considerations

### 🔒 **Safe Practices**
- Always review scripts before running: `curl -fsSL <url> | less`
- Use HTTPS URLs to prevent man-in-the-middle attacks
- Script uses temporary directories with cleanup
- No persistent system modifications outside project directory

### 🛡️ **Transparency**
- All source code is public and reviewable
- No hidden downloads or external dependencies
- Clear logging of all operations
- Fail-fast error handling

## Docker Development Environment (v2.6.0)

### Quick Start with Docker
The Docker mode provides a complete containerized development environment, eliminating setup friction:

```bash
# Generate application with Docker support
ruby scripts/create_tasker_app.rb build my-app --docker --with-observability

# Navigate to your app
cd tasker-applications/my-app

# Start the development environment
./bin/docker-dev up          # Core services only
./bin/docker-dev up-full     # Include observability stack
```

### Docker Development Commands
The `./bin/docker-dev` helper script provides 15+ commands for Docker management:

**Service Management**
```bash
./bin/docker-dev up          # Start core services
./bin/docker-dev up-full     # Start with observability
./bin/docker-dev down        # Stop all services
./bin/docker-dev restart     # Restart app service
./bin/docker-dev status      # Show service status
```

**Development Tools**
```bash
./bin/docker-dev console     # Rails console
./bin/docker-dev bash        # Shell access
./bin/docker-dev logs        # View all logs
./bin/docker-dev logs-app    # View app logs only
```

**Database Operations**
```bash
./bin/docker-dev migrate     # Run migrations
./bin/docker-dev setup       # Run Tasker setup
./bin/docker-dev reset-db    # Reset database (destructive)
```

**Testing & Validation**
```bash
./bin/docker-dev test        # Run test suite
./bin/docker-dev validate    # Run integration validations
```

### Docker Architecture
- **Multi-stage Dockerfile**: Optimized for development and production
- **Service orchestration**: PostgreSQL, Redis, Rails app, and optional observability
- **Volume mounts**: Live code reloading with persistent data
- **Health checks**: Automatic service dependency management
- **Network isolation**: Secure bridge network for all services

## Dry-Run Validation System (v2.6.0)

### Overview
The generator includes a comprehensive dry-run validation system that tests template consistency without generating files:

```bash
# Run all validations
ruby scripts/create_tasker_app.rb dry_run

# Run specific validation modes
ruby scripts/create_tasker_app.rb dry_run --mode=templates  # File existence
ruby scripts/create_tasker_app.rb dry_run --mode=syntax     # ERB/Ruby/YAML syntax
ruby scripts/create_tasker_app.rb dry_run --mode=cli        # CLI option mapping
ruby scripts/create_tasker_app.rb dry_run --mode=bindings   # Template variables

# Validate Docker templates
ruby scripts/create_tasker_app.rb dry_run --docker --with-observability
```

### Validation Categories

**1. Template File Existence**
- Verifies all required ERB templates exist
- Adapts to Docker/observability modes
- Reports missing templates with paths

**2. ERB Template Syntax**
- Parses all ERB templates for syntax errors
- Validates without executing templates
- Catches malformed Ruby blocks and expressions

**3. Generated Code Syntax**
- Renders templates with test data
- Validates Ruby syntax using RubyVM::InstructionSequence
- Validates YAML syntax using YAML.safe_load
- Tests actual generated output, not just templates

**4. CLI Options Mapping**
- Ensures all Thor options have corresponding instance variables
- Validates required methods exist
- Handles renamed variables (e.g., `--docker` → `@docker_mode`)

**5. Template Variable Bindings**
- Tests templates can render with expected contexts
- Validates all required variables are available
- Tests step handlers, configuration, and Docker bindings

### Example Output
```
🧪 Starting Dry Run Validation...
📋 Mode: all
🏗️  Tasks: ecommerce, inventory, customer
🐳 Docker mode: enabled
📊 Observability: enabled

📁 Validating template files existence...
  ✅ 14 templates found
🔧 Validating ERB template syntax...
  ✅ 19 ERB templates valid
💎 Validating Ruby template output syntax...
  ✅ 4 Ruby templates generate valid syntax
📄 Validating YAML template output syntax...
  ✅ 4 YAML templates generate valid syntax
⚙️  Validating CLI options mapping...
  ✅ 17 CLI mappings valid
🔗 Validating template variable bindings...
  ✅ 5 binding contexts valid

🎯 Overall Result:
✅ All validations passed! (63 checks)
```

### CI/CD Integration
The dry-run system is perfect for CI/CD pipelines:
- Zero file system impact
- Clear exit codes (0 for success, 1 for failure)
- Detailed error reporting
- Sub-second execution time

## Development Setup

### For Contributors

If you're developing or testing the installer:

```bash
# Test locally without network
./scripts/install-tasker-app.sh --help

# Test with local templates
ruby scripts/create_tasker_app.rb build test-app \
  --templates-dir ./scripts/templates \
  --non-interactive

# Run comprehensive validation
ruby scripts/create_tasker_app.rb dry_run --mode=all

# Test Docker generation
ruby scripts/create_tasker_app.rb build docker-app \
  --docker --with-observability
```

### Repository Setup

To host this installer on your GitHub repository:

1. **Update URLs** in `scripts/install-tasker-app.sh`:
   ```bash
   GITHUB_REPO="tasker-systems/tasker"  # Your actual GitHub repo
   BRANCH="main"                  # Your default branch
   ```

2. **Ensure Files Are Public**:
   - `scripts/install-tasker-app.sh`
   - `scripts/create_tasker_app.rb`
   - All files in `scripts/templates/`

3. **Test the URLs**:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/scripts/install-tasker-app.sh
   ```

## Example Usage Flows

### Marketing/Conference Flow
```bash
# Conference presentation or documentation
curl -fsSL https://install.tasker.dev | bash
```

### Developer Evaluation
```bash
# Quick evaluation with specific use case
curl -fsSL https://install.tasker.dev | bash -s -- \
  --app-name my-evaluation-app \
  --tasks ecommerce \
  --non-interactive
```

### Tutorial/Workshop
```bash
# Guided setup for workshops
curl -fsSL https://install.tasker.dev | bash -s -- \
  --app-name workshop-app \
  --interactive
```

## Integration Examples

Once installed, developers can immediately:

### 🔍 **Explore APIs**
- GraphQL Playground: `http://localhost:3000/tasker/graphql`
- REST API Docs: `http://localhost:3000/tasker/api-docs`
- Health Endpoints: `http://localhost:3000/tasker/health/status`

### 🚀 **Execute Workflows**
```ruby
# Create and run an e-commerce order processing task
task = Tasker::HandlerFactory.instance.get(
  'order_processing',
  namespace_name: 'ecommerce',
  version: '1.0.0'
).initialize_task!(
  Tasker::Types::TaskRequest.new(
    name: 'order_processing',
    namespace: 'ecommerce',
    context: { cart_id: 123, user_id: 456 }
  )
)
```

### 📈 **Monitor Observability**
- Metrics: `http://localhost:3000/tasker/metrics`
- Configure your observability backend via `OTEL_EXPORTER_OTLP_ENDPOINT`
- View structured logs with correlation IDs

This generator transforms Tasker from "interesting project" to "production application" in under 5 minutes, providing an exceptional developer experience that showcases enterprise-grade workflow orchestration capabilities.
