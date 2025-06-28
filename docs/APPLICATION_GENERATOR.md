# Tasker Application Template Generator

The Tasker Application Template Generator provides a one-line creation experience for building production-ready applications that leverage Tasker's enterprise workflow orchestration capabilities.

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
