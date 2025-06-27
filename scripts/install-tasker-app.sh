#!/bin/bash
set -e

# Tasker Application Template Generator
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/jcoletaylor/tasker/main/scripts/install-tasker-app.sh | bash
#
#   Or with options:
#   curl -fsSL https://raw.githubusercontent.com/jcoletaylor/tasker/main/scripts/install-tasker-app.sh | bash -s -- --app-name my-tasker-app --templates ecommerce,inventory
#
# This script downloads and runs the Tasker application template generator

# Configuration
GITHUB_REPO="jcoletaylor/tasker"  # Update this to your actual repo
BRANCH="demo-app-builder"
SCRIPT_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/${BRANCH}/scripts/create_tasker_app.rb"
TEMPLATES_BASE_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/${BRANCH}/scripts/templates"
TEMP_DIR="/tmp/tasker-app-generator-$$"
SCRIPT_NAME="create_tasker_app.rb"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

log_header() {
    echo -e "${CYAN}🚀 $1${NC}"
}

# Cleanup function
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

# Platform detection
detect_platform() {
    local platform
    case "$(uname -s)" in
        Darwin*) platform="macos" ;;
        Linux*)  platform="linux" ;;
        MINGW*|MSYS*|CYGWIN*) platform="windows" ;;
        *) platform="unknown" ;;
    esac
    echo "$platform"
}

# Dependency checks
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 is required but not installed. Please install $1 and try again."
    fi
}

check_dependencies() {
    log_info "Checking system dependencies..."

    # Essential tools
    check_command "ruby"
    check_command "rails"
    check_command "git"

    # Download tools (prefer curl, fallback to wget)
    if command -v curl &> /dev/null; then
        DOWNLOAD_CMD="curl -fsSL"
    elif command -v wget &> /dev/null; then
        DOWNLOAD_CMD="wget -qO-"
    else
        log_error "Either curl or wget is required for downloading files"
    fi

    # Check Ruby version
    local ruby_version=$(ruby -v | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    local ruby_major=$(echo "$ruby_version" | cut -d. -f1)
    local ruby_minor=$(echo "$ruby_version" | cut -d. -f2)

    if [ "$ruby_major" -lt 3 ] || ([ "$ruby_major" -eq 3 ] && [ "$ruby_minor" -lt 0 ]); then
        log_error "Ruby 3.0+ is required. Found: $ruby_version"
    fi

    # Check Rails version
    local rails_version=$(rails -v | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    local rails_major=$(echo "$rails_version" | cut -d. -f1)

    if [ "$rails_major" -lt 7 ]; then
        log_warning "Rails 7+ is recommended. Found: $rails_version"
    fi

    log_success "All dependencies satisfied"
}

# Download function with retry logic
download_file() {
    local url="$1"
    local output="$2"
    local retries=3

    for i in $(seq 1 $retries); do
        if [ "$i" -gt 1 ]; then
            log_info "Retry $((i-1))/$((retries-1))..."
            sleep 2
        fi

        if $DOWNLOAD_CMD "$url" > "$output" 2>/dev/null; then
            return 0
        fi
    done

    log_error "Failed to download $url after $retries attempts"
}

# Download templates directory structure
download_templates() {
    local templates_dir="$1"

    log_info "Downloading application templates..."

    # List of template files to download
    local template_files=(
        "task_handlers/api_step_handler.rb.erb"
        "task_handlers/calculation_step_handler.rb.erb"
        "task_handlers/database_step_handler.rb.erb"
        "task_handlers/notification_step_handler.rb.erb"
        "task_definitions/configured_task.rb.erb"
        "task_definitions/task_handler.rb.erb"
        "task_definitions/ecommerce_task.yaml.erb"
        "task_definitions/inventory_task.yaml.erb"
        "task_definitions/customer_task.yaml.erb"
        "configuration/tasker_configuration.rb.erb"
        "documentation/README.md.erb"
        "tests/task_handler_spec.rb.erb"
    )

    for template_file in "${template_files[@]}"; do
        local url="${TEMPLATES_BASE_URL}/${template_file}"
        local output_file="${templates_dir}/${template_file}"
        local output_dir=$(dirname "$output_file")

        # Create directory if it doesn't exist
        mkdir -p "$output_dir"

        # Download file
        download_file "$url" "$output_file"
    done

    log_success "Templates downloaded successfully"
}

# Main installation process
main() {
    log_header "Tasker Application Template Generator"
    echo

    local platform=$(detect_platform)
    log_info "Detected platform: $platform"

    # Check dependencies
    check_dependencies
    echo

    # Create temporary directory
    mkdir -p "$TEMP_DIR"
    log_info "Using temporary directory: $TEMP_DIR"

    # Download the main Ruby script
    log_info "Downloading Tasker application generator script..."
    download_file "$SCRIPT_URL" "$TEMP_DIR/$SCRIPT_NAME"
    log_success "Application generator script downloaded"

    # Download templates
    download_templates "$TEMP_DIR/templates"

    # Make script executable
    chmod +x "$TEMP_DIR/$SCRIPT_NAME"

    # Prepare arguments for Thor command structure
    local script_args=("build")  # Start with the command
    local app_name=""
    local custom_args=()

    # Always add templates directory
    custom_args+=("--templates-dir" "$TEMP_DIR/templates")

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --app-name)
                app_name="$2"
                shift 2
                ;;
            --app-name=*)
                app_name="${1#*=}"
                shift
                ;;
            --non-interactive)
                custom_args+=("--interactive" "false")
                shift
                ;;
            --no-observability)
                custom_args+=("--observability" "false")
                shift
                ;;
            --skip-tests)
                custom_args+=("--skip-tests" "true")
                shift
                ;;
            --api-base-url)
                custom_args+=("--api-base-url" "$2")
                shift 2
                ;;
            --api-base-url=*)
                custom_args+=("--api-base-url" "${1#*=}")
                shift
                ;;
            *)
                custom_args+=("$1")
                shift
                ;;
        esac
    done

    # Set default app name if not provided
    if [ -z "$app_name" ]; then
        app_name="my-tasker-app"
    fi

    # Build final arguments: command + app_name + options
    script_args+=("$app_name")
    script_args+=("${custom_args[@]}")

    echo
    log_header "Running Tasker Application Generator"
    echo

    # Run the Ruby script
    cd "$TEMP_DIR"
    ruby "$SCRIPT_NAME" "${script_args[@]}"

    echo
    log_success "Tasker application generation completed!"

    # Provide next steps
    echo
    log_header "Next Steps:"
    echo "1. cd into your new Tasker application directory"
    echo "2. Start Redis: redis-server (or docker run -d -p 6379:6379 redis)"
    echo "3. Start Sidekiq: bundle exec sidekiq"
    echo "4. Start Rails: bundle exec rails server"
    echo "5. Visit http://localhost:3000/tasker/graphql for GraphQL playground"
    echo "6. Visit http://localhost:3000/tasker/api-docs for REST API documentation"
    echo "7. Visit http://localhost:3000/tasker/metrics for Prometheus metrics"
    echo
    log_header "Infrastructure Ready:"
    echo "✅ PostgreSQL database with all Tasker migrations"
    echo "✅ Redis caching and session storage"
    echo "✅ Sidekiq background job processing"
    echo "✅ OpenTelemetry observability stack (if enabled)"
    echo "✅ Complete workflow examples ready to test"
    echo
    echo "For more information, visit: https://github.com/${GITHUB_REPO}"
}

# Help function
show_help() {
    echo "Tasker Application Template Generator"
    echo
    echo "Usage:"
    echo "  curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/${BRANCH}/scripts/install-tasker-app.sh | bash"
    echo
    echo "With options:"
    echo "  curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/${BRANCH}/scripts/install-tasker-app.sh | bash -s -- [OPTIONS]"
    echo
    echo "Options:"
    echo "  --app-name NAME           Name of the Tasker application (default: my-tasker-app)"
    echo "  --tasks LIST              Comma-separated list of application templates to include"
    echo "                           Options: ecommerce,inventory,customer (default: all)"
    echo "  --output-dir DIR          Directory to create application (default: ./tasker-applications)"
    echo "  --no-observability        Skip OpenTelemetry and Prometheus configuration"
    echo "  --non-interactive         Skip interactive prompts"
    echo "  --skip-tests              Skip test suite generation"
    echo "  --api-base-url URL        Base URL for DummyJSON API (default: https://dummyjson.com)"
    echo "  --help                    Show this help message"
    echo
    echo "Examples:"
    echo "  # Create with defaults (interactive)"
    echo "  curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/${BRANCH}/scripts/install-tasker-app.sh | bash"
    echo
    echo "  # Create specific application"
    echo "  curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/${BRANCH}/scripts/install-tasker-app.sh | bash -s -- --app-name my-ecommerce-app --tasks ecommerce"
    echo
          echo "  # Non-interactive creation"
    echo "  curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/${BRANCH}/scripts/install-tasker-app.sh | bash -s -- --non-interactive"
}

# Check for help flag
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    show_help
    exit 0
fi

# Run main function
main "$@"
