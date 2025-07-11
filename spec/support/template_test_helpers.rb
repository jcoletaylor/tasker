# frozen_string_literal: true

module TemplateTestHelpers
  # Render an ERB template with the given bindings
  def render_template(template_name, bindings)
    # Use the engine's root directory, not Rails.root (which points to the dummy app)
    engine_root = Tasker::Engine.root
    template_path = File.join(engine_root, "lib/generators/tasker/templates/#{template_name}")
    erb_template = ERB.new(File.read(template_path))
    binding_context = create_binding_context(bindings)
    erb_template.result(binding_context)
  end

  # Create a binding context with instance variables set from the bindings hash
  def create_binding_context(bindings)
    binding_object = Object.new

    # Set instance variables from bindings
    bindings.each do |key, value|
      binding_object.instance_variable_set("@#{key}", value)
    end

    binding_object.instance_eval { binding }
  end

  # Validate that Ruby code is syntactically correct
  def validate_ruby_syntax(code)
    RubyVM::InstructionSequence.compile(code)
    true
  rescue SyntaxError => e
    puts "Ruby syntax error: #{e.message}"
    puts 'Code that failed:'
    puts code
    false
  end

  # Validate that YAML is syntactically correct
  def validate_yaml_syntax(yaml_content)
    YAML.safe_load(yaml_content)
    true
  rescue Psych::SyntaxError => e
    puts "YAML syntax error: #{e.message}"
    puts 'YAML that failed:'
    puts yaml_content
    false
  end

  # Debug helper to show rendered template output
  def debug_template_output(template_name, bindings)
    rendered = render_template(template_name, bindings)
    puts "=== #{template_name} with #{bindings.inspect} ==="
    puts rendered
    puts "=== End #{template_name} ==="
    rendered
  end
end
