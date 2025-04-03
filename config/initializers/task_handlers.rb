# # frozen_string_literal: true

# # Auto-load all YAML task handler configurations at application startup
# if defined?(Rails)
#   Rails.application.config.after_initialize do
#     # Paths to look for YAML task handlers
#     yaml_paths = [
#       Rails.root.join('app/task_handlers/**/*.{yaml,yml}'),
#       Rails.root.join('lib/task_handlers/**/*.{yaml,yml}')
#     ]

#     # Additional paths in development/test environments
#     yaml_paths << Rails.root.join('spec/examples/**/tasks/*.{yaml,yml}') if Rails.env.local?

#     # Find all YAML files
#     yaml_files = yaml_paths.flat_map { |path| Dir.glob(path) }

#     if yaml_files.any?
#       Rails.logger.info "Loading #{yaml_files.count} YAML task handler configurations..."

#       yaml_files.each do |yaml_path|
#         Rails.logger.debug { "Building task handler from #{yaml_path}" }
#         handler_class = Tasker::TaskBuilder.from_yaml(yaml_path).build
#         Rails.logger.debug { "Registered task handler: #{handler_class}" }
#       rescue StandardError => e
#         Rails.logger.error "Error loading YAML task handler from #{yaml_path}: #{e.message}"
#         Rails.logger.debug e.backtrace.join("\n") if Rails.env.development?
#       end

#       Rails.logger.info 'Finished loading YAML task handlers'
#     end
#   end
# end
