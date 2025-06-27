#!/usr/bin/env ruby
# frozen_string_literal: true

# Tasker 2.5.0 - Application Template Generator
#
# Creates production-ready Rails applications with Tasker's
# enterprise workflow orchestration capabilities using real-world
# business patterns and API integrations.
#
# This is a comprehensive application template generator that follows
# the REAL workflow that developers would use:
# 1. Install Tasker gem from RubyGems
# 2. Use Rails generators to scaffold workflows
# 3. Apply enterprise-grade templates and configurations
#
# Usage: ruby scripts/create_tasker_app.rb build [APP_NAME]

require 'English'
require 'thor'
require 'erb'
require 'fileutils'
require 'yaml'

class TaskerAppGenerator < Thor
  TEMPLATES_DIR = File.expand_path('templates', __dir__)
  TASKER_VERSION = '~> 2.5.0' # Use latest stable version

  desc 'build [APP_NAME]', 'Generate a complete Tasker application with enterprise templates'
  option :app_name, default: 'my-tasker-app', desc: 'Name of the generated Tasker application'
  option :tasks, type: :array, default: %w[ecommerce inventory customer],
                 desc: 'Application templates to include'
  option :output_dir, default: './tasker-applications', desc: 'Directory to create application'
  option :observability, type: :boolean, default: true, desc: 'Include OpenTelemetry and Prometheus configuration'
  option :interactive, type: :boolean, default: true, desc: 'Interactive setup with guided prompts'
  option :skip_tests, type: :boolean, default: false, desc: 'Skip test suite generation'
  option :api_base_url, default: 'https://dummyjson.com', desc: 'Base URL for DummyJSON API (for example workflows)'
  option :templates_dir, default: nil, desc: 'Directory containing ERB templates (defaults to scripts/templates)'

  def build(app_name = nil)
    @app_name = app_name || options[:app_name]
    @tasks = options[:tasks]
    @output_dir = options[:output_dir]
    @templates_dir = options[:templates_dir] || TEMPLATES_DIR
    @api_base_url = options[:api_base_url]

    say "🚀 Generating Tasker Application: #{@app_name}", :green
    say "📋 Selected templates: #{@tasks.join(', ')}", :cyan
    say "📍 Output directory: #{@output_dir}", :cyan
    say "🔗 Using Tasker gem version: #{TASKER_VERSION}", :cyan

    confirm_settings if options[:interactive]

    create_output_directory
    create_rails_app
    add_tasker_gem
    setup_tasker_integration
    generate_tasks_using_generators
    enhance_with_demo_templates
    setup_observability_configuration if options[:observability]
    generate_documentation

    say '✅ Tasker application generated successfully!', :green
    say "📍 Location: #{File.join(@output_dir, @app_name)}", :cyan
    display_next_steps
  end

  desc 'list_templates', 'List available application templates'
  def list_templates
    say '📋 Available Application Templates:', :green

    available_templates = %w[ecommerce inventory customer]
    available_templates.each do |template|
      say "  • #{template}: #{task_description(template)}", :cyan
    end
  end

  desc 'validate_environment', 'Validate that all dependencies are available'
  def validate_environment
    say '🔍 Validating Environment...', :green

    # Check for Rails
    rails_version = `rails --version 2>/dev/null`
    if $CHILD_STATUS.success?
      say "✅ Rails: #{rails_version.strip}", :green
    else
      say '❌ Rails not found', :red
      exit 1
    end

    # Check for Ruby version
    say "✅ Ruby: #{RUBY_VERSION}", :green

    # Check for templates directory
    if Dir.exist?(@templates_dir || TEMPLATES_DIR)
      say "✅ Templates directory: #{@templates_dir || TEMPLATES_DIR}", :green
    else
      say "❌ Templates directory not found: #{@templates_dir || TEMPLATES_DIR}", :red
      exit 1
    end

    say '🎉 Environment validation passed!', :green
  end

  private

  def confirm_settings
    return unless yes?('Continue with these settings? (y/n)')

    if yes?('Customize template selection? (y/n)')
      say 'Available templates: ecommerce, inventory, customer'
      custom_tasks = ask('Enter templates (comma-separated):', default: @tasks.join(','))
      @tasks = custom_tasks.split(',').map(&:strip)
    end

    return unless yes?('Change output directory? (y/n)')

    @output_dir = ask('Output directory:', default: @output_dir)
  end

  def create_output_directory
    say '📁 Creating output directory...', :blue
    FileUtils.mkdir_p(@output_dir)
  end

  def create_rails_app
    say '📦 Creating Rails application...', :blue

    app_path = File.join(@output_dir, @app_name)

    if Dir.exist?(app_path)
      if yes?("Directory #{app_path} already exists. Remove it? (y/n)")
        FileUtils.rm_rf(app_path)
      else
        say '❌ Aborting: Directory already exists', :red
        exit 1
      end
    end

    # Create Rails API app
    run "rails new #{app_path} --api --skip-test --skip-bootsnap --skip-listen --quiet"
    @app_dir = app_path

    say '  ✓ Rails app created', :green
  end

  def add_tasker_gem
    say '💎 Adding Tasker gem...', :blue

    # Add Tasker gem to Gemfile (using real gem, not local path)
    gemfile_path = File.join(@app_dir, 'Gemfile')
    tasker_gem_line = "\n# Tasker workflow orchestration\ngem 'tasker', '#{TASKER_VERSION}'\n"

    # Add additional gems needed for demo
    additional_gems = <<~GEMS

      # Additional gems for Tasker demo functionality
      gem 'faraday', '~> 2.0'  # For API integrations
      gem 'rack-cors'          # For CORS in demo
    GEMS

    File.open(gemfile_path, 'a') do |f|
      f.write(tasker_gem_line)
      f.write(additional_gems)
    end

    say '  ✓ Tasker gem added to Gemfile', :green
  end

  def setup_tasker_integration
    say '⚙️  Setting up Tasker integration...', :blue

    Dir.chdir(@app_dir) do
      # Bundle install
      say '  📦 Installing gems...', :cyan
      run 'bundle install --quiet'
      say '  ✓ Gems installed', :green

      # Install Tasker using the real generator
      say '  🛠️  Running Tasker install generator...', :cyan
      run 'rails generate tasker:install --quiet'
      say '  ✓ Tasker installed', :green

      # Setup database
      say '  🗄️  Setting up database...', :cyan
      run 'rails db:create --quiet'
      run 'rails db:migrate --quiet'
      say '  ✓ Database setup', :green
    end
  end

  def generate_tasks_using_generators
    say '🏗️  Generating tasks using Rails generators...', :blue

    Dir.chdir(@app_dir) do
      @tasks.each do |task_type|
        task_config = load_task_configuration(task_type)

        say "  📋 Generating #{task_type} task using rails generate...", :cyan

        # Use the actual Tasker Rails generator
        step_names = task_config[:steps].map { |step| step[:name] }
        generator_cmd = "rails generate tasker:task_handler #{task_config[:task_name]} " \
                        "--namespace_name=#{task_config[:namespace]} " \
                        '--version=1.0.0 ' \
                        "--description='#{task_config[:description]}' " \
                        "--steps=#{step_names.join(',')}"

        run generator_cmd
        say "    ✓ #{task_type} base task generated", :green
      end
    end
  end

  def enhance_with_demo_templates
    say '🎨 Enhancing with application-specific templates...', :blue

    @tasks.each do |task_type|
      say "  🔧 Enhancing #{task_type} task...", :cyan

      task_config = load_task_configuration(task_type)

      # Override the generated YAML config with our demo-specific one
      enhance_yaml_configuration(task_config)

      # Generate our specialized step handlers
      generate_demo_step_handlers(task_config)

      # Add our enhanced task handler with demo features
      enhance_task_handler(task_config)

      say "    ✓ #{task_type} task enhanced", :green
    end

    # Generate demo-specific configuration
    generate_demo_configuration
  end

  def enhance_yaml_configuration(task_config)
    yaml_path = File.join(@app_dir, 'config', 'tasker', 'tasks', "#{task_config[:task_name]}.yaml")

    # Generate enhanced YAML config with DummyJSON endpoints
    yaml_content = generate_demo_yaml_config(task_config)
    File.write(yaml_path, yaml_content)
  end

  def generate_demo_step_handlers(task_config)
    task_config[:steps].each do |step|
      template_key = determine_handler_template(step)
      template_path = File.join(@templates_dir, 'task_handlers', "#{template_key}.rb.erb")

      unless File.exist?(template_path)
        say "    ⚠️  Template not found: #{template_path}", :yellow
        next
      end

      template = ERB.new(File.read(template_path))
      rendered_content = template.result(binding_from_step_config(task_config, step))

      # Write to the same location where the generator put the step handlers
      output_dir = File.join(@app_dir, 'app', 'tasks', task_config[:namespace])
      output_path = File.join(output_dir, "#{step[:name]}_step_handler.rb")
      File.write(output_path, rendered_content)
    end
  end

  def enhance_task_handler(task_config)
    # Use our ConfiguredTask template instead of the manual definition
    task_template_path = File.join(@templates_dir, 'task_definitions', 'configured_task.rb.erb')

    return unless File.exist?(task_template_path)

    template = ERB.new(File.read(task_template_path))
    rendered_content = template.result(binding_from_config(task_config))

    # Write the ConfiguredTask to the correct location
    output_dir = File.join(@app_dir, 'app', 'tasks', task_config[:namespace])
    FileUtils.mkdir_p(output_dir)
    output_path = File.join(output_dir, "#{task_config[:task_name]}.rb")
    File.write(output_path, rendered_content)
  end

  def generate_demo_configuration
    # Generate enhanced Tasker configuration for production use
    config_template_path = File.join(@templates_dir, 'configuration', 'tasker_configuration.rb.erb')

    return unless File.exist?(config_template_path)

    template = ERB.new(File.read(config_template_path))
    rendered_content = template.result(binding)

    # Replace the generated initializer with our enhanced one
    initializer_path = File.join(@app_dir, 'config', 'initializers', 'tasker.rb')
    File.write(initializer_path, rendered_content)
  end

  def setup_observability_configuration
    say '📊 Setting up observability configuration...', :blue

    # Add OpenTelemetry initializer for demo
    otel_initializer = <<~RUBY
      # OpenTelemetry configuration for Tasker demo
      # This showcases how to configure OpenTelemetry for any compatible backend
      # (Jaeger is used here as an example, but any OTLP-compatible system works)

      if Rails.env.development? || Rails.env.production?
        require 'opentelemetry/sdk'
        require 'opentelemetry/auto_instrumenter'

        OpenTelemetry::SDK.configure do |c|
          c.service_name = '#{@app_name}'
          c.service_version = '1.0.0'

          # Configure exporter - Jaeger is one example of many OTLP-compatible targets
          # Other options: Zipkin, Honeycomb, Datadog, New Relic, etc.
          c.add_span_processor(
            OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
              OpenTelemetry::Exporter::OTLP::Exporter.new(
                endpoint: ENV['OTEL_EXPORTER_OTLP_ENDPOINT'] || 'http://localhost:14268/api/traces'
              )
            )
          )
        end

        OpenTelemetry::AutoInstrumenter.install
      end
    RUBY

    otel_path = File.join(@app_dir, 'config', 'initializers', 'opentelemetry.rb')
    File.write(otel_path, otel_initializer)

    say '  ✓ OpenTelemetry configuration added', :green
    say '  📝 Note: Jaeger used as example - any OTLP-compatible backend works', :cyan
  end

  def generate_documentation
    say '📚 Generating documentation...', :blue

    # Generate README using our template
    readme_template_path = File.join(@templates_dir, 'documentation', 'README.md.erb')
    return unless File.exist?(readme_template_path)

    template = ERB.new(File.read(readme_template_path))
    rendered_content = template.result(binding)

    readme_path = File.join(@app_dir, 'README.md')
    File.write(readme_path, rendered_content)

    say '  ✓ README.md generated', :green
  end

  def display_next_steps
    say "\n🎯 Next Steps:", :green
    say "1. cd #{File.join(@output_dir, @app_name)}", :cyan
    say '2. bundle exec rails server', :cyan
    say '3. Visit the generated tasks in app/tasks/', :cyan
    say '4. Check the enhanced YAML configs in config/tasker/tasks/', :cyan
    say "5. Test workflows using Tasker's GraphQL or REST APIs", :cyan
    say '', :cyan
    say '📖 API Documentation available at:', :green
    say '   • GraphQL: http://localhost:3000/tasker/graphql', :cyan
    say '   • REST API: http://localhost:3000/tasker/api-docs', :cyan
    say '', :cyan
    return unless options[:observability]

    say '📊 Observability:', :green
    say '   • Metrics: http://localhost:3000/tasker/metrics', :cyan
    say '   • Configure OTEL_EXPORTER_OTLP_ENDPOINT for your observability backend', :cyan
  end

  # Generate YAML configuration from templates
  def generate_demo_yaml_config(task_config)
    yaml_template_path = File.join(@templates_dir, 'task_definitions', "#{task_config[:namespace]}_task.yaml.erb")

    # Process ERB template - we control all templates so this should always work
    template = ERB.new(File.read(yaml_template_path))
    template.result(binding)
  end

  # Load task configuration from YAML templates
  def load_task_configuration(task_type)
    yaml_template_path = File.join(@templates_dir, 'task_definitions', "#{task_type}_task.yaml.erb")

    raise "Task configuration template not found: #{yaml_template_path}" unless File.exist?(yaml_template_path)

    # Process ERB template
    template = ERB.new(File.read(yaml_template_path))
    rendered_yaml = template.result(binding)

    # Parse YAML and convert to hash with symbol keys for consistency
    yaml_data = YAML.safe_load(rendered_yaml)

    # Convert to the expected format with symbol keys where needed
    {
      namespace: yaml_data['namespace_name'],
      task_name: yaml_data['name']&.split('/')&.last || yaml_data['task_handler_class']&.underscore,
      description: yaml_data['description'],
      required_context_fields: yaml_data.dig('schema', 'required') || [],
      context_schema: yaml_data.dig('schema', 'properties')&.transform_keys(&:to_sym) || {},
      has_annotations: false, # Demo-specific field, not from YAML
      annotation_type_name: nil, # Demo-specific field, not from YAML
      steps: yaml_data['step_templates']&.map { |step| step.transform_keys(&:to_sym) } || [],
      module_namespace: yaml_data['module_namespace'],
      task_handler_class: yaml_data['task_handler_class'],
      version: yaml_data['version'],
      default_dependent_system: yaml_data['default_dependent_system'],
      named_steps: yaml_data['named_steps']
    }
  end

  # Helper methods for binding context
  def binding_from_config(config)
    namespace = config[:namespace]
    task_name = config[:task_name]
    steps = config[:steps]
    required_context_fields = config[:required_context_fields] || []
    context_schema = config[:context_schema] || {}
    has_annotations = config[:has_annotations] || false
    annotation_type_name = config[:annotation_type_name] || "#{task_name}_annotation"

    binding
  end

  def binding_from_step_config(task_config, step_config)
    namespace = task_config[:namespace]
    task_name = task_config[:task_name]
    step_name = step_config[:name]
    step_type = step_config[:step_type] || 'generic'
    step_description = step_config[:description]
    api_endpoint = step_config[:api_endpoint]
    api_method = step_config[:api_method] || 'GET'
    api_params = step_config[:api_params] || {}
    timeout = step_config[:timeout] || 30
    retry_limit = step_config[:retry_limit] || 3
    handler_type = step_config[:handler_type] || 'api'

    binding
  end

  def determine_handler_template(step)
    case step[:handler_type]
    when 'api', 'external_service'
      'api_step_handler'
    when 'calculation'
      'calculation_step_handler'
    when 'database'
      'database_step_handler'
    when 'notification'
      'notification_step_handler'
    else
      'api_step_handler' # Default to API handler
    end
  end

  # Task descriptions for CLI help
  def task_description(task_type)
    case task_type
    when 'ecommerce'
      'Complete order lifecycle from cart validation to fulfillment'
    when 'inventory'
      'Automated stock monitoring and supplier coordination'
    when 'customer'
      'User registration and onboarding workflows'
    else
      'Unknown task type'
    end
  end
end

# Run the CLI if called directly
TaskerAppGenerator.start(ARGV) if __FILE__ == $PROGRAM_NAME
