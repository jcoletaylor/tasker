# frozen_string_literal: true

require_relative 'lib/tasker/version'

Gem::Specification.new do |spec|
  spec.name        = 'tasker-engine'
  spec.version     = Tasker::VERSION
  spec.authors     = ['Pete Taylor']
  spec.email       = ['pete.jc.taylor@hey.com']
  spec.homepage    = 'https://github.com/tasker-systems/tasker'
  spec.summary     = 'Enterprise-grade workflow orchestration engine for Rails applications'
  spec.description = 'Tasker is a comprehensive workflow orchestration engine that provides ' \
                     'multi-step task processing, dependency management, state machine transitions, ' \
                     'and enterprise observability features including OpenTelemetry tracing and ' \
                     'Prometheus metrics for Rails applications.'
  spec.license     = 'MIT'
  spec.required_ruby_version = Gem::Requirement.new('>= 3.2.0')

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/tasker-systems/tasker'

  spec.files = Dir['{app,config,db,docs,lib}/**/*', 'LICENSE', 'Rakefile', 'README.md']

  spec.add_dependency 'logger', '~> 1.6'
  spec.add_dependency 'rails', '~> 7.2.2'
  # Use postgresql as the database for Active Record
  spec.add_dependency 'pg', '~> 1.5'
  # Use Puma as the app server
  spec.add_dependency 'puma', '~> 6.6'

  # Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin AJAX possible
  spec.add_dependency 'active_model_serializers', '~> 0.10', '>= 0.10.0'
  spec.add_dependency 'rack-cors', '~> 2.0'

  spec.add_dependency 'json-schema', '~> 2.4', '>= 2.4.0'

  spec.add_dependency 'concurrent-ruby', '~> 1.3.5'
  spec.add_dependency 'concurrent-ruby-ext', '~> 1.3.5'
  spec.add_dependency 'dry-events', '~> 1.1'
  spec.add_dependency 'dry-struct', '~> 1.8'
  spec.add_dependency 'dry-types', '~> 1.8'
  spec.add_dependency 'dry-validation', '~> 1.10'

  spec.add_dependency 'faraday', '~> 2.12.2'
  spec.add_dependency 'graphql', '~> 2.0'
  spec.add_dependency 'jwt', '~> 2.10.0'

  spec.add_dependency 'kamal', '~> 1.9'

  spec.add_dependency 'opentelemetry-exporter-otlp', '~> 0.30.0'
  spec.add_dependency 'opentelemetry-sdk', '~> 1.8.0'

  spec.add_dependency 'scenic', '~> 1.8'
  spec.add_dependency 'statesman', '~> 12.0.0'

  spec.metadata['rubygems_mfa_required'] = 'true'
end
