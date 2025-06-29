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
require 'active_support/core_ext/string'

class TaskerAppGenerator < Thor
  TEMPLATES_DIR = File.expand_path('templates', __dir__)
  TASKER_VERSION = '~> 2.6.0' # Use latest published version

  # Fix Thor deprecation warning
  def self.exit_on_failure?
    true
  end

  desc 'build [APP_NAME]', 'Generate a complete Tasker application with enterprise templates'
  option :app_name, default: 'my-tasker-app', desc: 'Name of the generated Tasker application'
  option :tasks, type: :array, default: %w[ecommerce inventory customer],
                 desc: 'Application templates to include'
  option :output_dir, default: './tasker-applications', desc: 'Directory to create application'
  option :observability, type: :boolean, default: true, desc: 'Include OpenTelemetry and Prometheus configuration'
  option :interactive, type: :boolean, default: true, desc: 'Interactive setup with guided prompts'
  option :skip_tests, type: :boolean, default: false, desc: 'Skip test suite generation'
  option :api_base_url, default: 'https://dummyjson.com', desc: 'Base URL for DummyJSON API (for example workflows)'
  option :docker, type: :boolean, default: false, desc: 'Generate Docker-based development environment'
  option :with_observability, type: :boolean, default: false,
                              desc: 'Include Jaeger and Prometheus in Docker setup (requires --docker)'
  option :templates_dir, default: nil, desc: 'Internal: Directory containing ERB templates', hide: true

  def build(app_name = nil)
    @app_name = app_name || options[:app_name]
    @tasks = options[:tasks]
    @output_dir = options[:output_dir]
    @templates_dir = options[:templates_dir] || TEMPLATES_DIR
    @api_base_url = options[:api_base_url]
    @docker_mode = options[:docker]
    @with_observability = options[:with_observability]
    @observability = options[:observability]
    @interactive = options[:interactive]
    @skip_tests = options[:skip_tests]

    say "🚀 Generating Tasker Application: #{@app_name}", :green
    say "📋 Selected templates: #{@tasks.join(', ')}", :cyan
    say "📍 Output directory: #{@output_dir}", :cyan
    say "🔗 Using Tasker gem version: #{TASKER_VERSION}", :cyan

    # Validate templates directory and required files
    validate_templates_directory

    # Validate Docker options
    if @with_observability && !@docker_mode
      say '⚠️  --with-observability requires --docker flag', :yellow
      @with_observability = false
    end

    confirm_settings if options[:interactive]

    create_output_directory

    if @docker_mode
      say '🐳 Generating Docker-based development environment...', :blue
      generate_docker_setup
    else
      say '🏗️  Generating traditional Rails setup...', :blue
      create_rails_app
      add_tasker_gem
      setup_tasker_integration
      generate_tasks_using_generators
      enhance_with_demo_templates
      setup_observability_configuration if options[:observability]
    end

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

  desc 'dry_run', 'Perform comprehensive validation without generating files'
  option :mode, type: :string, default: 'all', desc: 'Validation mode: all, templates, syntax, cli, bindings'
  option :tasks, type: :array, default: %w[ecommerce inventory customer], desc: 'Tasks to validate'
  option :docker, type: :boolean, default: false, desc: 'Include Docker template validation'
  option :with_observability, type: :boolean, default: false, desc: 'Include observability template validation'
  def dry_run
    @templates_dir = TEMPLATES_DIR
    @tasks = options[:tasks]
    @docker_mode = options[:docker]
    @docker = options[:docker] # Add for CLI validation
    @with_observability = options[:with_observability]
    @app_name = 'test-validation-app'
    @output_dir = './test-output'
    @api_base_url = 'https://dummyjson.com'
    @observability = options.fetch(:observability, true)
    @interactive = options.fetch(:interactive, false)
    @skip_tests = options.fetch(:skip_tests, true)

    say '🧪 Starting Dry Run Validation...', :green
    say "📋 Mode: #{options[:mode]}", :cyan
    say "🏗️  Tasks: #{@tasks.join(', ')}", :cyan
    say "🐳 Docker mode: #{@docker_mode ? 'enabled' : 'disabled'}", :cyan
    say "📊 Observability: #{@with_observability ? 'enabled' : 'disabled'}", :cyan
    say '', :cyan

    validation_results = {}

    case options[:mode]
    when 'all'
      validation_results.merge!(validate_templates)
      validation_results.merge!(validate_erb_syntax)
      validation_results.merge!(validate_ruby_syntax)
      validation_results.merge!(validate_yaml_syntax)
      validation_results.merge!(validate_cli_options)
      validation_results.merge!(validate_template_bindings)
    when 'templates'
      validation_results.merge!(validate_templates)
    when 'syntax'
      validation_results.merge!(validate_erb_syntax)
      validation_results.merge!(validate_ruby_syntax)
      validation_results.merge!(validate_yaml_syntax)
    when 'cli'
      validation_results.merge!(validate_cli_options)
    when 'bindings'
      validation_results.merge!(validate_template_bindings)
    else
      say "❌ Unknown validation mode: #{options[:mode]}", :red
      exit 1
    end

    display_validation_results(validation_results)
  end

  private

  # Validation Methods for Dry Run
  def validate_templates
    say '📁 Validating template files existence...', :blue
    results = { templates: { passed: [], failed: [] } }

    required_templates = [
      'task_definitions/ecommerce_task.yaml.erb',
      'task_definitions/inventory_task.yaml.erb',
      'task_definitions/customer_task.yaml.erb',
      'task_handlers/api_step_handler.rb.erb',
      'task_handlers/calculation_step_handler.rb.erb',
      'configuration/tasker_configuration.rb.erb',
      'documentation/README.md.erb',
      'task_definitions/configured_task.rb.erb'
    ]

    # Add Docker templates if Docker mode enabled
    if @docker_mode
      required_templates += [
        'docker/Dockerfile.erb',
        'docker/docker-compose.yml.erb',
        'docker/database.yml.erb',
        'docker/docker-dev.erb',
        'docker/prometheus.yml.erb',
        'docker/README.md.erb'
      ]
    end

    required_templates.each do |template|
      template_path = File.join(@templates_dir, template)
      if File.exist?(template_path)
        results[:templates][:passed] << template
      else
        results[:templates][:failed] << template
      end
    end

    say "  ✅ #{results[:templates][:passed].length} templates found", :green
    say "  ❌ #{results[:templates][:failed].length} templates missing", :red if results[:templates][:failed].any?

    results
  end

  def validate_erb_syntax
    say '🔧 Validating ERB template syntax...', :blue
    results = { erb_syntax: { passed: [], failed: [] } }

    # Find all ERB templates
    erb_files = Dir.glob(File.join(@templates_dir, '**', '*.erb'))

    erb_files.each do |erb_file|
      relative_path = erb_file.sub("#{@templates_dir}/", '')

      begin
        content = File.read(erb_file)
        erb = ERB.new(content)
        erb.src # This will raise if syntax is invalid
        results[:erb_syntax][:passed] << relative_path
      rescue StandardError => e
        results[:erb_syntax][:failed] << { file: relative_path, error: e.message }
      end
    end

    say "  ✅ #{results[:erb_syntax][:passed].length} ERB templates valid", :green
    say "  ❌ #{results[:erb_syntax][:failed].length} ERB templates invalid", :red if results[:erb_syntax][:failed].any?

    results
  end

  def validate_ruby_syntax
    say '💎 Validating Ruby template output syntax...', :blue
    results = { ruby_syntax: { passed: [], failed: [] } }

    # Test Ruby ERB templates by rendering them with test data
    ruby_templates = [
      'task_handlers/api_step_handler.rb.erb',
      'task_handlers/calculation_step_handler.rb.erb',
      'configuration/tasker_configuration.rb.erb',
      'task_definitions/configured_task.rb.erb'
    ]

    ruby_templates.each do |template|
      template_path = File.join(@templates_dir, template)
      next unless File.exist?(template_path)

      begin
        erb = ERB.new(File.read(template_path))
        rendered = erb.result(test_binding_for_ruby_templates)

        # Check Ruby syntax using RubyVM::InstructionSequence
        RubyVM::InstructionSequence.compile(rendered)
        results[:ruby_syntax][:passed] << template
      rescue StandardError => e
        results[:ruby_syntax][:failed] << { file: template, error: e.message }
      end
    end

    say "  ✅ #{results[:ruby_syntax][:passed].length} Ruby templates generate valid syntax", :green
    if results[:ruby_syntax][:failed].any?
      say "  ❌ #{results[:ruby_syntax][:failed].length} Ruby templates generate invalid syntax",
          :red
    end

    results
  end

  def validate_yaml_syntax
    say '📄 Validating YAML template output syntax...', :blue
    results = { yaml_syntax: { passed: [], failed: [] } }

    yaml_templates = [
      'task_definitions/ecommerce_task.yaml.erb',
      'task_definitions/inventory_task.yaml.erb',
      'task_definitions/customer_task.yaml.erb'
    ]

    yaml_templates << 'docker/prometheus.yml.erb' if @docker_mode

    yaml_templates.each do |template|
      template_path = File.join(@templates_dir, template)
      next unless File.exist?(template_path)

      begin
        erb = ERB.new(File.read(template_path))
        rendered = erb.result(test_binding_for_yaml_templates)

        # Parse YAML to check syntax
        YAML.safe_load(rendered)
        results[:yaml_syntax][:passed] << template
      rescue StandardError => e
        results[:yaml_syntax][:failed] << { file: template, error: e.message }
      end
    end

    say "  ✅ #{results[:yaml_syntax][:passed].length} YAML templates generate valid syntax", :green
    if results[:yaml_syntax][:failed].any?
      say "  ❌ #{results[:yaml_syntax][:failed].length} YAML templates generate invalid syntax",
          :red
    end

    results
  end

  def validate_cli_options
    say '⚙️  Validating CLI options mapping...', :blue
    results = { cli_options: { passed: [], failed: [] } }

    # Get all defined options for the build command
    build_command = self.class.commands['build']
    option_names = build_command.options.keys

    # Check that each option has a corresponding instance variable or method
    option_names.each do |option_name|
      # Special cases for renamed instance variables
      instance_var_name = case option_name
                          when 'docker'
                            '@docker_mode'
                          when 'with_observability'
                            '@with_observability'
                          else
                            "@#{option_name}"
                          end

      if respond_to?("#{option_name}=") || instance_variable_defined?(instance_var_name)
        results[:cli_options][:passed] << option_name
      else
        results[:cli_options][:failed] << option_name
      end
    end

    # Validate that key methods exist for option processing
    required_methods = %w[build validate_templates_directory confirm_settings create_output_directory]
    required_methods += if @docker_mode
                          %w[generate_docker_setup docker_binding]
                        else
                          %w[create_rails_app add_tasker_gem setup_tasker_integration]
                        end

    required_methods.each do |method_name|
      if respond_to?(method_name, true) # true includes private methods
        results[:cli_options][:passed] << "method:#{method_name}"
      else
        results[:cli_options][:failed] << "method:#{method_name}"
      end
    end

    say "  ✅ #{results[:cli_options][:passed].length} CLI mappings valid", :green
    say "  ❌ #{results[:cli_options][:failed].length} CLI mappings missing", :red if results[:cli_options][:failed].any?

    results
  end

  def validate_template_bindings
    say '🔗 Validating template variable bindings...', :blue
    results = { bindings: { passed: [], failed: [] } }

    # Test that templates can be rendered with expected binding contexts
    binding_tests = [
      {
        templates: ['task_handlers/api_step_handler.rb.erb'],
        binding_method: :test_binding_for_step_handlers,
        description: 'step handler binding'
      },
      {
        templates: ['configuration/tasker_configuration.rb.erb'],
        binding_method: :test_binding_for_config,
        description: 'configuration binding'
      },
      {
        templates: ['task_definitions/configured_task.rb.erb'],
        binding_method: :test_binding_for_task_config,
        description: 'task configuration binding'
      }
    ]

    if @docker_mode
      binding_tests << {
        templates: ['docker/docker-compose.yml.erb', 'docker/README.md.erb'],
        binding_method: :docker_binding,
        description: 'Docker binding'
      }
    end

    binding_tests.each do |test|
      test[:templates].each do |template|
        template_path = File.join(@templates_dir, template)
        next unless File.exist?(template_path)

        begin
          erb = ERB.new(File.read(template_path))
          test_binding = send(test[:binding_method])
          erb.result(test_binding)
          results[:bindings][:passed] << "#{template} (#{test[:description]})"
        rescue StandardError => e
          results[:bindings][:failed] << {
            file: template,
            binding: test[:description],
            error: e.message
          }
        end
      end
    end

    say "  ✅ #{results[:bindings][:passed].length} binding contexts valid", :green
    say "  ❌ #{results[:bindings][:failed].length} binding contexts failed", :red if results[:bindings][:failed].any?

    results
  end

  def display_validation_results(results)
    say "\n📊 Validation Summary:", :green

    total_passed = 0
    total_failed = 0

    results.each do |category, data|
      passed_count = data[:passed].length
      failed_count = data[:failed].length
      total_passed += passed_count
      total_failed += failed_count

      status_color = failed_count.positive? ? :red : :green
      status_icon = failed_count.positive? ? '❌' : '✅'

      say "  #{status_icon} #{category.to_s.capitalize}: #{passed_count} passed, #{failed_count} failed", status_color

      # Show detailed failures
      next unless failed_count.positive? && data[:failed].is_a?(Array)

      data[:failed].each do |failure|
        if failure.is_a?(Hash)
          say "    • #{failure[:file]}: #{failure[:error]}", :red
        else
          say "    • #{failure}", :red
        end
      end
    end

    say "\n🎯 Overall Result:", :cyan
    if total_failed.zero?
      say "✅ All validations passed! (#{total_passed} checks)", :green
      exit 0
    else
      say "❌ #{total_failed} validation(s) failed out of #{total_passed + total_failed} total", :red
      exit 1
    end
  end

  # Test binding methods for validation
  def test_binding_for_ruby_templates
    # Provide all variables that Ruby templates might need
    namespace = 'demo'
    task_name = 'test_task'
    step_name = 'test_step'
    step_type = 'api'
    step_description = 'Test step description'
    api_endpoint = 'https://api.example.com/test'
    api_method = 'GET'
    api_params = {}
    timeout = 30
    retry_limit = 3
    handler_type = 'api'
    app_name = @app_name
    api_base_url = 'https://dummyjson.com'
    binding
  end

  def test_binding_for_yaml_templates
    # YAML templates need simpler binding
    api_base_url = 'https://dummyjson.com'
    binding
  end

  def test_binding_for_step_handlers
    binding_from_step_config(
      { namespace: 'demo', task_name: 'test_task' },
      {
        name: 'test_step',
        step_type: 'api',
        description: 'Test step',
        api_endpoint: '/test',
        api_method: 'GET',
        api_params: {},
        timeout: 30,
        retry_limit: 3,
        handler_type: 'api'
      }
    )
  end

  def test_binding_for_config
    app_name = @app_name
    binding
  end

  def test_binding_for_task_config
    # Use the actual binding_from_config method with proper data
    test_config = {
      namespace: 'demo',
      task_name: 'test_task',
      steps: [{ name: 'test_step', step_type: 'api' }],
      required_context_fields: ['id'],
      context_schema: { id: 'string' },
      has_annotations: false,
      annotation_type_name: 'test_annotation'
    }

    binding_from_config(test_config)
  end

  def validate_templates_directory
    say '📋 Validating templates directory...', :blue

    unless Dir.exist?(@templates_dir)
      say "❌ Templates directory does not exist: #{@templates_dir}", :red
      exit 1
    end

    # Check for required template files
    required_templates = [
      'task_definitions/ecommerce_task.yaml.erb',
      'task_definitions/inventory_task.yaml.erb',
      'task_definitions/customer_task.yaml.erb',
      'task_handlers/api_step_handler.rb.erb',
      'task_handlers/calculation_step_handler.rb.erb',
      'configuration/tasker_configuration.rb.erb',
      'documentation/README.md.erb'
    ]

    missing_templates = []
    required_templates.each do |template|
      template_path = File.join(@templates_dir, template)
      missing_templates << template unless File.exist?(template_path)
    end

    if missing_templates.any?
      say '❌ Missing required template files:', :red
      missing_templates.each do |template|
        say "  • #{template}", :red
      end
      say "\n📁 Available templates:", :cyan
      Dir.glob(File.join(@templates_dir, '**', '*.erb')).each do |file|
        say "  • #{file.sub("#{@templates_dir}/", '')}", :cyan
      end
      exit 1
    end

    say '✅ All required templates found', :green
  end

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

    # Create Rails API app (need to change directory to avoid Rails directory conflict)
    current_dir = Dir.pwd
    begin
      Dir.chdir(@output_dir)
      system("rails new #{@app_name} --api --skip-test --skip-bootsnap --skip-listen --quiet --database=postgresql")
      unless $CHILD_STATUS.success?
        say '❌ Failed to create Rails app', :red
        exit 1
      end
    ensure
      Dir.chdir(current_dir)
    end
    @app_dir = app_path

    say '  ✓ Rails app created', :green
  end

  def add_tasker_gem
    say '💎 Adding Tasker gem...', :blue

    gemfile_path = File.join(@app_dir, 'Gemfile')

    # First, uncomment the redis gem that's already in the Gemfile by default
    say '  🔧 Enabling Redis gem...', :cyan
    gemfile_content = File.read(gemfile_path)
    redis_uncommented = false

    if gemfile_content.include?('# gem "redis"')
      updated_content = gemfile_content.gsub('# gem "redis"', 'gem "redis"')
      File.write(gemfile_path, updated_content)
      redis_uncommented = true
      say '  ✓ Redis gem enabled', :green
    elsif /^\s*gem\s+['"]redis['"]/.match?(gemfile_content)
      # Redis is already uncommented
      redis_uncommented = true
      say '  ✓ Redis gem already enabled', :green
    else
      say '  ⚠️  Redis gem not found in default form, will add manually', :yellow
    end

    # Add Tasker gem to Gemfile using git source (no authentication required)
    tasker_gem_lines = <<~GEMS

      # Tasker workflow orchestration
      gem 'tasker', git: 'https://github.com/tasker-systems/tasker.git', tag: 'v#{TASKER_VERSION.gsub('~> ', '')}'
    GEMS

    # Add production-ready infrastructure gems
    infrastructure_gems = <<~GEMS

      # Production infrastructure for Tasker demo
    GEMS

    # Only add Redis if we didn't successfully uncomment it
    infrastructure_gems += "  gem 'redis', '~> 5.0'  # Redis for caching and job queuing\n" unless redis_uncommented

    infrastructure_gems += "  gem 'sidekiq', '~> 7.0'  # Background job processing\n"

    # Add observability gems if observability is enabled
    observability_gems = ''
    if options[:observability]
      observability_gems = <<~GEMS

        # OpenTelemetry observability stack
        gem 'opentelemetry-sdk'
        gem 'opentelemetry-instrumentation-all'
        gem 'opentelemetry-exporter-otlp'
      GEMS
    end

    # Add additional utility gems needed for demo
    additional_gems = <<~GEMS

      # Additional gems for Tasker demo functionality
      gem 'faraday', '~> 2.0'  # For API integrations
      gem 'rack-cors'          # For CORS in demo
    GEMS

    File.open(gemfile_path, 'a') do |f|
      f.write(tasker_gem_lines)
      f.write(infrastructure_gems)
      f.write(observability_gems) if options[:observability]
      f.write(additional_gems)
    end

    say '  ✓ Tasker gem added to Gemfile (using git source)', :green
    say '  ✓ Infrastructure gems added (Sidekiq)', :green
    if options[:observability]
      say '  ✓ OpenTelemetry observability gems added', :green
    else
      say '  ⚪ Observability gems skipped (use --observability to include)', :cyan
    end
  end

  def setup_tasker_integration
    say '⚙️  Setting up Tasker integration...', :blue

    Dir.chdir(@app_dir) do
      # Bundle install
      say '  📦 Installing gems...', :cyan
      system('bundle install --quiet')
      unless $CHILD_STATUS.success?
        say '❌ Failed to install gems', :red
        exit 1
      end
      say '  ✓ Gems installed', :green

      # Install Tasker migrations
      say '  📋 Installing Tasker migrations...', :cyan
      system('bundle exec rails tasker:install:migrations --quiet')
      unless $CHILD_STATUS.success?
        say '❌ Failed to install Tasker migrations', :red
        exit 1
      end
      say '  ✓ Tasker migrations installed', :green

      # NOTE: Database objects (views/functions) will be installed via rake task after setup
      say '  📊 Database objects will be installed after Tasker setup...', :cyan

      # Setup database
      say '  🗄️  Setting up database...', :cyan
      system('bundle exec rails db:create --quiet')
      unless $CHILD_STATUS.success?
        say '❌ Failed to create database', :red
        exit 1
      end

      # Run migrations (including Tasker migrations)
      system('bundle exec rails db:migrate --quiet')
      unless $CHILD_STATUS.success?
        say '❌ Failed to run migrations', :red
        exit 1
      end
      say '  ✓ Database setup and migrations completed', :green

      # Run Tasker setup
      say '  🛠️  Running Tasker setup...', :cyan
      system('bundle exec rails tasker:setup --quiet')
      unless $CHILD_STATUS.success?
        say '❌ Failed to run Tasker setup', :red
        exit 1
      end
      say '  ✓ Tasker setup completed', :green

      # Install Tasker database objects (views and functions) - now that gem is loaded
      say '  📊 Installing Tasker database objects...', :cyan
      system('bundle exec rake tasker:install:database_objects --quiet')
      if $CHILD_STATUS.success?
        say '  ✓ Tasker database objects installed', :green
      else
        say '❌ Failed to install Tasker database objects', :red
        say '⚠️  Some migrations may fail without required database views and functions', :yellow
        say '💡 You can manually run: bundle exec rake tasker:install:database_objects', :cyan
      end

      # Add Tasker engine mount to routes
      say '  🛤️  Setting up Tasker routes...', :cyan
      routes_file = File.join(@app_dir, 'config', 'routes.rb')

      unless File.exist?(routes_file)
        say "    ❌ Routes file not found: #{routes_file}", :red
        exit 1
      end

      routes_content = File.read(routes_file)

      if routes_content.include?('mount Tasker::Engine')
        say '    ✓ Tasker routes already configured', :green
      elsif routes_content.include?('Rails.application.routes.draw do')
        # Add Tasker mount to routes - be more careful about the insertion
        new_routes = routes_content.gsub(
          /(Rails\.application\.routes\.draw do\s*\n)/,
          "\\1  mount Tasker::Engine, at: '/tasker', as: 'tasker'\n"
        )

        begin
          File.write(routes_file, new_routes)
          say '    ✓ Tasker routes added', :green
        rescue StandardError => e
          say "    ❌ Failed to update routes file: #{e.message}", :red
          exit 1
        end
      else
        say '    ❌ Could not find Rails.application.routes.draw block in routes file', :red
        say "    📝 Please manually add: mount Tasker::Engine, at: '/tasker', as: 'tasker'", :yellow
      end
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

        system(generator_cmd)
        unless $CHILD_STATUS.success?
          say "❌ Failed to generate #{task_type} task", :red
          exit 1
        end
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
      FileUtils.mkdir_p(output_dir)
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

      if defined?(OpenTelemetry)
        require 'opentelemetry/sdk'
        require 'opentelemetry-exporter-otlp'
        require 'opentelemetry/instrumentation/all'

        # Configure OpenTelemetry
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

          # Add the OTLP exporter
          c.add_span_processor(
            OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(otlp_exporter)
          )

          # Configure resource with additional attributes
          c.resource = OpenTelemetry::SDK::Resources::Resource.create({
                                                                        'service.name' => '#{@app_name}',
                                                                        'service.version' => '1.0.0',
                                                                        'service.framework' => 'tasker'
                                                                      })

          # Use all auto-instrumentations except Faraday (which has a known bug)
          # The Faraday instrumentation incorrectly passes Faraday::Response objects instead of status codes
          # causing "undefined method `to_i' for #<Faraday::Response>" errors
          c.use_all({ 'OpenTelemetry::Instrumentation::Faraday' => { enabled: false } })
        end
      end

      # Add Sidekiq configuration for background job processing
      if defined?(Sidekiq)
        Sidekiq.configure_server do |config|
          config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }
        end

        Sidekiq.configure_client do |config|
          config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }
        end
      end
    RUBY

    otel_path = File.join(@app_dir, 'config', 'initializers', 'opentelemetry.rb')
    File.write(otel_path, otel_initializer)

    say '  ✓ OpenTelemetry configuration added', :green
    say '  ✓ Sidekiq configuration added', :green
    say '  📝 Note: Jaeger used as example - any OTLP-compatible backend works', :cyan
  end

  def generate_documentation
    say '📚 Generating documentation...', :blue

    # Skip README generation in Docker mode (already generated in generate_docker_files)
    if @docker_mode
      say '  ✓ Documentation already generated (Docker mode)', :green
      return
    end

    # Generate README using our template
    readme_template_path = File.join(@templates_dir, 'documentation', 'README.md.erb')
    return unless File.exist?(readme_template_path)

    template = ERB.new(File.read(readme_template_path))
    rendered_content = template.result(binding)

    readme_path = File.join(@app_dir, 'README.md')
    File.write(readme_path, rendered_content)

    say '  ✓ README.md generated', :green
  end

  def generate_docker_setup
    say '  🐳 Setting up Docker-based development environment...', :cyan

    @app_dir = File.join(@output_dir, @app_name)

    # Create application directory structure
    FileUtils.mkdir_p(@app_dir)

    # Generate basic Rails structure without rails new
    create_rails_structure_for_docker

    # Copy Docker configuration files
    generate_docker_files

    # Add Tasker configuration to Rails structure
    setup_tasker_for_docker

    # Generate task handlers using our templates
    generate_tasks_for_docker

    # Generate validation scripts
    generate_validation_scripts

    say '  ✅ Docker environment generated successfully', :green
  end

  def create_rails_structure_for_docker
    say '    📁 Creating Rails application structure...', :cyan

    # Create essential Rails directories
    %w[
      app/controllers app/models app/jobs app/mailers app/views
      app/tasks bin config config/environments config/initializers
      config/locales config/tasker config/tasker/tasks
      db db/migrate lib log public tmp storage
      test spec vendor
    ].each do |dir|
      FileUtils.mkdir_p(File.join(@app_dir, dir))
    end

    # Create essential Rails files
    create_rails_config_files_for_docker
    create_rails_application_files_for_docker

    say '    ✅ Rails structure created', :green
  end

  def create_rails_config_files_for_docker
    # Generate Gemfile
    gemfile_content = generate_docker_gemfile
    File.write(File.join(@app_dir, 'Gemfile'), gemfile_content)

    # Generate application.rb
    application_rb = generate_docker_application_rb
    File.write(File.join(@app_dir, 'config', 'application.rb'), application_rb)

    # Generate routes.rb with Tasker mount
    routes_rb = generate_docker_routes_rb
    File.write(File.join(@app_dir, 'config', 'routes.rb'), routes_rb)

    # Generate environments
    %w[development test production].each do |env|
      env_config = generate_docker_environment_config(env)
      File.write(File.join(@app_dir, 'config', 'environments', "#{env}.rb"), env_config)
    end

    # Generate boot.rb and environment.rb
    File.write(File.join(@app_dir, 'config', 'boot.rb'), generate_docker_boot_rb)
    File.write(File.join(@app_dir, 'config', 'environment.rb'), generate_docker_environment_rb)
  end

  def create_rails_application_files_for_docker
    # Generate application controller
    app_controller = generate_docker_application_controller
    File.write(File.join(@app_dir, 'app', 'controllers', 'application_controller.rb'), app_controller)

    # Generate Rakefile
    rakefile = generate_docker_rakefile
    File.write(File.join(@app_dir, 'Rakefile'), rakefile)

    # Generate config.ru
    config_ru = generate_docker_config_ru
    File.write(File.join(@app_dir, 'config.ru'), config_ru)
  end

  def generate_docker_files
    say '    🐳 Copying Docker configuration files...', :cyan

    docker_templates = %w[
      Dockerfile docker-compose.yml database.yml
      docker-dev prometheus.yml README.md
    ]

    docker_templates.each do |template_name|
      template_path = File.join(@templates_dir, 'docker', "#{template_name}.erb")

      unless File.exist?(template_path)
        say "      ⚠️  Docker template not found: #{template_path}", :yellow
        next
      end

      template = ERB.new(File.read(template_path))
      rendered_content = template.result(docker_binding)

      case template_name
      when 'docker-dev'
        output_path = File.join(@app_dir, 'bin', 'docker-dev')
        FileUtils.mkdir_p(File.dirname(output_path))
        File.write(output_path, rendered_content)
        FileUtils.chmod(0o755, output_path) # Make executable
      when 'database.yml'
        output_path = File.join(@app_dir, 'config', 'database.yml')
        File.write(output_path, rendered_content)
      when 'README.md'
        output_path = File.join(@app_dir, 'README.md')
        File.write(output_path, rendered_content)
      else
        output_path = File.join(@app_dir, template_name)
        File.write(output_path, rendered_content)
      end
    end

    say '    ✅ Docker files generated', :green
  end

  def setup_tasker_for_docker
    say '    ⚙️  Setting up Tasker configuration...', :cyan

    # Generate Tasker initializer
    generate_demo_configuration

    # Generate OpenTelemetry configuration if observability is enabled
    setup_observability_configuration if @with_observability

    say '    ✅ Tasker configuration complete', :green
  end

  def generate_tasks_for_docker
    say '    🏗️  Generating task handlers...', :cyan

    @tasks.each do |task_type|
      task_config = load_task_configuration(task_type)

      # Generate YAML configuration
      enhance_yaml_configuration(task_config)

      # Generate step handlers
      generate_demo_step_handlers(task_config)

      # Generate task handler
      enhance_task_handler(task_config)

      say "      ✅ #{task_type} task generated", :green
    end

    say '    ✅ All tasks generated', :green
  end

  def generate_validation_scripts
    say '    🧪 Generating validation scripts...', :cyan

    scripts_dir = File.join(@app_dir, 'scripts')
    FileUtils.mkdir_p(scripts_dir)

    # Generate Jaeger validation script
    jaeger_script = generate_jaeger_validation_script
    File.write(File.join(scripts_dir, 'validate_jaeger_integration.rb'), jaeger_script)

    # Generate Prometheus validation script
    prometheus_script = generate_prometheus_validation_script
    File.write(File.join(scripts_dir, 'validate_prometheus_integration.rb'), prometheus_script)

    say '    ✅ Validation scripts generated', :green
  end

  def display_next_steps
    if @docker_mode
      display_docker_next_steps
    else
      display_traditional_next_steps
    end
  end

  def display_docker_next_steps
    say "\n🎯 Next Steps:", :green
    say "1. cd #{File.join(@output_dir, @app_name)}", :cyan
    say '2. ./bin/docker-dev up          # Start core services', :cyan
    say '3. ./bin/docker-dev up-full     # OR start with observability', :cyan
    say '', :cyan
    say '🐳 Docker Commands:', :green
    say '   • ./bin/docker-dev console   # Rails console', :cyan
    say '   • ./bin/docker-dev bash      # Shell access', :cyan
    say '   • ./bin/docker-dev logs      # View logs', :cyan
    say '   • ./bin/docker-dev migrate   # Run migrations', :cyan
    say '   • ./bin/docker-dev setup     # Run Tasker setup', :cyan
    say '   • ./bin/docker-dev test      # Run tests', :cyan
    say '   • ./bin/docker-dev validate  # Test integrations', :cyan
    say '', :cyan
    say '📍 Application URLs:', :green
    say '   • App: http://localhost:3000', :cyan
    say '   • Tasker API: http://localhost:3000/tasker', :cyan
    if @with_observability
      say '   • Jaeger UI: http://localhost:16686', :cyan
      say '   • Prometheus: http://localhost:9090', :cyan
    end
    say '', :cyan
    say '📖 Documentation:', :green
    say '   • Full setup guide in README.md', :cyan
    say '   • Docker commands reference in ./bin/docker-dev --help', :cyan
  end

  def display_traditional_next_steps
    say "\n🎯 Next Steps:", :green
    say "1. cd #{File.join(@output_dir, @app_name)}", :cyan
    say '2. Start Redis: redis-server (or use Docker: docker run -d -p 6379:6379 redis)', :cyan
    say '3. Start Sidekiq: bundle exec sidekiq', :cyan
    say '4. bundle exec rails server', :cyan
    say '5. Visit the generated tasks in app/tasks/', :cyan
    say '6. Check the enhanced YAML configs in config/tasker/tasks/', :cyan
    say "7. Test workflows using Tasker's GraphQL or REST APIs", :cyan
    say '', :cyan
    say '📖 API Documentation available at:', :green
    say '   • GraphQL: http://localhost:3000/tasker/graphql', :cyan
    say '   • REST API: http://localhost:3000/tasker/api-docs', :cyan
    say '', :cyan
    say '🔧 Infrastructure:', :green
    say '   • Redis: Required for caching and job queuing', :cyan
    say '   • Sidekiq: Background job processing at /sidekiq', :cyan
    say '   • Set REDIS_URL environment variable if using non-default Redis', :cyan
    say '', :cyan
    say '💡 Database Objects:', :green
    say '   • Views and functions automatically installed via rake task', :cyan
    say '   • If installation failed, manually run: bundle exec rake tasker:install:database_objects', :cyan
    say '   • Required for proper migration execution and database views', :cyan
    say '', :cyan
    return unless options[:observability]

    say '📊 Observability:', :green
    say '   • Metrics: http://localhost:3000/tasker/metrics', :cyan
    say '   • Configure OTEL_EXPORTER_OTLP_ENDPOINT for your observability backend', :cyan
    say '   • Example: export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:14268/api/traces', :cyan
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

    unless File.exist?(yaml_template_path)
      say "    ❌ Task configuration template not found: #{yaml_template_path}", :red
      say "    📁 Available templates in #{@templates_dir}:", :cyan
      if Dir.exist?(@templates_dir)
        Dir.glob(File.join(@templates_dir, '**', '*.erb')).each do |file|
          say "      • #{file.sub("#{@templates_dir}/", '')}", :cyan
        end
      else
        say "    ❌ Templates directory does not exist: #{@templates_dir}", :red
      end
      raise "Task configuration template not found: #{yaml_template_path}"
    end

    begin
      # Process ERB template
      template = ERB.new(File.read(yaml_template_path))
      rendered_yaml = template.result(binding)

      # Parse YAML and convert to hash with symbol keys for consistency
      yaml_data = YAML.safe_load(rendered_yaml)

      raise "Invalid YAML structure - expected Hash, got #{yaml_data.class}" unless yaml_data.is_a?(Hash)

      # Convert to the expected format with symbol keys where needed
      {
        namespace: yaml_data['namespace_name'] || 'default',
        task_name: yaml_data['name']&.split('/')&.last || yaml_data['task_handler_class']&.underscore || task_type,
        description: yaml_data['description'] || "#{task_type.capitalize} workflow",
        required_context_fields: yaml_data.dig('schema', 'required') || [],
        context_schema: yaml_data.dig('schema', 'properties')&.transform_keys(&:to_sym) || {},
        has_annotations: false, # Demo-specific field, not from YAML
        annotation_type_name: nil, # Demo-specific field, not from YAML
        steps: yaml_data['step_templates']&.map do |step|
          step_hash = step.transform_keys(&:to_sym)
          # Extract step_type and handler_type from handler_config if available
          if step_hash[:handler_config] && step_hash[:handler_config]['type']
            step_hash[:step_type] = step_hash[:handler_config]['type']
            step_hash[:handler_type] = step_hash[:handler_config]['type']
          end
          step_hash
        end || [],
        module_namespace: yaml_data['module_namespace'],
        task_handler_class: yaml_data['task_handler_class'],
        version: yaml_data['version'] || '1.0.0',
        default_dependent_system: yaml_data['default_dependent_system'],
        named_steps: yaml_data['named_steps']
      }
    rescue StandardError => e
      say "    ❌ Error processing template #{yaml_template_path}: #{e.message}", :red
      raise "Failed to load task configuration for #{task_type}: #{e.message}"
    end
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

  # Helper binding method for Docker templates
  def docker_binding
    app_name = @app_name
    tasks = @tasks
    with_observability = @with_observability
    namespace = 'demo' # Default namespace for Docker demos
    binding
  end

  # Helper methods for generating Rails files in Docker mode
  def generate_docker_gemfile
    <<~GEMFILE
      source 'https://rubygems.org'
      git_source(:github) { |repo| "https://github.com/\#{repo}.git" }

      ruby '#{RUBY_VERSION}'

      # Core Rails
      gem 'rails', '~> 7.0.0'
      gem 'pg', '~> 1.1'
      gem 'puma', '~> 5.0'
      gem 'redis', '~> 5.0'

      # Tasker workflow orchestration
      gem 'tasker', git: 'https://github.com/tasker-systems/tasker.git', tag: 'v#{TASKER_VERSION.gsub('~> ', '')}'

      # Production infrastructure
      gem 'sidekiq', '~> 7.0'
      gem 'faraday', '~> 2.0'
      gem 'rack-cors'

      # Development and test
      group :development, :test do
        gem 'debug', platforms: %i[mri mingw x64_mingw]
        gem 'rspec-rails'
        gem 'factory_bot_rails'
      end

      group :development do
        gem 'listen', '~> 3.3'
        gem 'spring'
      end

      #{if @with_observability
          "# OpenTelemetry observability stack\ngem 'opentelemetry-sdk'\ngem 'opentelemetry-instrumentation-all'\ngem 'opentelemetry-exporter-otlp'"
        end}
    GEMFILE
  end

  def generate_docker_application_rb
    <<~RUBY
      require_relative "boot"

      require "rails"
      require "active_model/railtie"
      require "active_job/railtie"
      require "active_record/railtie"
      require "action_controller/railtie"
      require "action_mailer/railtie"
      require "action_view/railtie"
      require "action_cable/railtie"

      Bundler.require(*Rails.groups)

      module #{@app_name.classify}
        class Application < Rails::Application
          config.load_defaults 7.0
          config.api_only = true

          # CORS configuration for API access
          config.middleware.insert_before 0, Rack::Cors do
            allow do
              origins '*'
              resource '*', headers: :any, methods: [:get, :post, :put, :patch, :delete, :options, :head]
            end
          end
        end
      end
    RUBY
  end

  def generate_docker_routes_rb
    <<~RUBY
      Rails.application.routes.draw do
        mount Tasker::Engine, at: '/tasker', as: 'tasker'

        # Health check endpoint for Docker
        get '/health', to: proc { [200, {}, ['OK']] }
      end
    RUBY
  end

  def generate_docker_environment_config(env)
    case env
    when 'development'
      <<~RUBY
        require "active_support/core_ext/integer/time"

        Rails.application.configure do
          config.cache_classes = false
          config.eager_load = false
          config.consider_all_requests_local = true
          config.server_timing = true

          if Rails.root.join("tmp/caching-dev.txt").exist?
            config.cache_store = :memory_store
            config.public_file_server.headers = {
              "Cache-Control" => "public, max-age=\#{2.days.to_i}"
            }
          else
            config.action_controller.perform_caching = false
            config.cache_store = :null_store
          end

          config.active_record.migration_error = :page_load
          config.active_record.verbose_query_logs = true
          config.log_level = :debug
          config.log_tags = [:request_id]

          config.action_mailer.raise_delivery_errors = false
          config.action_mailer.perform_caching = false

          config.active_support.deprecation = :log
          config.active_support.disallowed_deprecation = :raise
          config.active_support.disallowed_deprecation_warnings = []

          config.active_record.dump_schema_after_migration = false

          # Allow connections from Docker containers
          config.hosts << "app"
          config.hosts << /.*\\.localhost/
        end
      RUBY
    when 'test'
      <<~RUBY
        require "active_support/core_ext/integer/time"

        Rails.application.configure do
          config.cache_classes = false
          config.action_view.cache_template_loading = true
          config.eager_load = false
          config.public_file_server.enabled = true
          config.public_file_server.headers = {
            "Cache-Control" => "public, max-age=\#{1.hour.to_i}"
          }

          config.consider_all_requests_local       = true
          config.action_controller.perform_caching = false
          config.cache_store = :null_store

          config.action_dispatch.show_exceptions = false
          config.action_controller.allow_forgery_protection = false
          config.active_support.deprecation = :stderr
          config.active_support.disallowed_deprecation = :raise
          config.active_support.disallowed_deprecation_warnings = []

          config.active_record.dump_schema_after_migration = false
        end
      RUBY
    when 'production'
      <<~RUBY
        require "active_support/core_ext/integer/time"

        Rails.application.configure do
          config.cache_classes = true
          config.eager_load = true
          config.consider_all_requests_local       = false
          config.public_file_server.enabled = ENV["RAILS_SERVE_STATIC_FILES"].present?

          config.log_level = :info
          config.log_tags = [:request_id]

          config.action_mailer.perform_caching = false
          config.i18n.fallbacks = true
          config.active_support.deprecation = :notify
          config.active_support.disallowed_deprecation = :log
          config.active_support.disallowed_deprecation_warnings = []

          config.log_formatter = ::Logger::Formatter.new

          if ENV["RAILS_LOG_TO_STDOUT"].present?
            logger           = ActiveSupport::Logger.new(STDOUT)
            logger.formatter = config.log_formatter
            config.logger    = ActiveSupport::TaggedLogging.new(logger)
          end

          config.active_record.dump_schema_after_migration = false
        end
      RUBY
    end
  end

  def generate_docker_boot_rb
    <<~RUBY
      ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../Gemfile', __dir__)

      require 'bundler/setup'
      require 'bootsnap/setup'
    RUBY
  end

  def generate_docker_environment_rb
    <<~RUBY
      require_relative "application"

      Rails.application.initialize!
    RUBY
  end

  def generate_docker_application_controller
    <<~RUBY
      class ApplicationController < ActionController::API
      end
    RUBY
  end

  def generate_docker_rakefile
    <<~RUBY
      require_relative "config/application"

      Rails.application.load_tasks
    RUBY
  end

  def generate_docker_config_ru
    <<~RUBY
      require_relative "config/environment"

      run Rails.application
      Rails.application.load_server
    RUBY
  end

  def generate_jaeger_validation_script
    <<~RUBY
      #!/usr/bin/env ruby
      # Jaeger integration validation script for #{@app_name}

      require 'net/http'
      require 'json'

      def test_jaeger_connection
        puts "🔍 Testing Jaeger connection..."

        uri = URI('http://jaeger:16686/api/services')
        response = Net::HTTP.get_response(uri)

        if response.code == '200'
          puts "✅ Jaeger API accessible"
          return true
        else
          puts "❌ Jaeger API not accessible: \#{response.code}"
          return false
        end
      rescue => e
        puts "❌ Failed to connect to Jaeger: \#{e.message}"
        return false
      end

      def test_otlp_endpoint
        puts "🔍 Testing OTLP endpoint..."

        # Check if OTLP endpoint is configured
        endpoint = ENV['OTEL_EXPORTER_OTLP_ENDPOINT'] || 'http://jaeger:14268/api/traces'
        uri = URI(endpoint.gsub('/api/traces', '/'))

        begin
          response = Net::HTTP.get_response(uri)
          puts "✅ OTLP endpoint reachable at \#{endpoint}"
          return true
        rescue => e
          puts "❌ OTLP endpoint not reachable: \#{e.message}"
          return false
        end
      end

      def main
        puts "🧪 Validating Jaeger Integration for #{@app_name}"
        puts "=" * 50

        jaeger_ok = test_jaeger_connection
        otlp_ok = test_otlp_endpoint

        puts "\\n📊 Results:"
        puts "Jaeger API: \#{jaeger_ok ? '✅' : '❌'}"
        puts "OTLP Endpoint: \#{otlp_ok ? '✅' : '❌'}"

        if jaeger_ok && otlp_ok
          puts "\\n🎉 Jaeger integration is working correctly!"
          exit 0
        else
          puts "\\n⚠️  Some Jaeger components are not working properly"
          exit 1
        end
      end

      main if __FILE__ == $0
    RUBY
  end

  def generate_prometheus_validation_script
    <<~RUBY
      #!/usr/bin/env ruby
      # Prometheus integration validation script for #{@app_name}

      require 'net/http'
      require 'json'

      def test_prometheus_connection
        puts "🔍 Testing Prometheus connection..."

        uri = URI('http://prometheus:9090/api/v1/targets')
        response = Net::HTTP.get_response(uri)

        if response.code == '200'
          puts "✅ Prometheus API accessible"
          return true
        else
          puts "❌ Prometheus API not accessible: \#{response.code}"
          return false
        end
      rescue => e
        puts "❌ Failed to connect to Prometheus: \#{e.message}"
        return false
      end

      def test_tasker_metrics_endpoint
        puts "🔍 Testing Tasker metrics endpoint..."

        uri = URI('http://app:3000/tasker/metrics')
        response = Net::HTTP.get_response(uri)

        if response.code == '200' && response.body.include?('tasker_')
          puts "✅ Tasker metrics endpoint responding with metrics"
          return true
        else
          puts "❌ Tasker metrics endpoint not working properly"
          return false
        end
      rescue => e
        puts "❌ Failed to reach Tasker metrics: \#{e.message}"
        return false
      end

      def test_prometheus_scraping
        puts "🔍 Testing Prometheus target scraping..."

        uri = URI('http://prometheus:9090/api/v1/targets')
        response = Net::HTTP.get_response(uri)

        if response.code == '200'
          data = JSON.parse(response.body)
          tasker_targets = data.dig('data', 'activeTargets')&.select { |t| t['job'] == 'tasker-app' }

          if tasker_targets && tasker_targets.any? { |t| t['health'] == 'up' }
            puts "✅ Prometheus is successfully scraping Tasker metrics"
            return true
          else
            puts "❌ Prometheus is not scraping Tasker targets properly"
            return false
          end
        end
      rescue => e
        puts "❌ Failed to check Prometheus targets: \#{e.message}"
        return false
      end

      def main
        puts "🧪 Validating Prometheus Integration for #{@app_name}"
        puts "=" * 50

        prometheus_ok = test_prometheus_connection
        metrics_ok = test_tasker_metrics_endpoint
        scraping_ok = test_prometheus_scraping

        puts "\\n📊 Results:"
        puts "Prometheus API: \#{prometheus_ok ? '✅' : '❌'}"
        puts "Tasker Metrics: \#{metrics_ok ? '✅' : '❌'}"
        puts "Prometheus Scraping: \#{scraping_ok ? '✅' : '❌'}"

        if prometheus_ok && metrics_ok && scraping_ok
          puts "\\n🎉 Prometheus integration is working correctly!"
          exit 0
        else
          puts "\\n⚠️  Some Prometheus components are not working properly"
          exit 1
        end
      end

      main if __FILE__ == $0
    RUBY
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
