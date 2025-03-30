# frozen_string_literal: true

require_relative 'lib/tasker/version'

Gem::Specification.new do |spec|
  spec.name        = 'tasker'
  spec.version     = Tasker::VERSION
  spec.authors     = ['Pete Taylor']
  spec.email       = ['pete.jc.taylor@hey.com']
  spec.homepage    = 'https://github.com/jcoletaylor/tasker'
  spec.summary     = 'Tasker Engine makes handling queuable multi-step tasks easy-ish'
  spec.description = 'Tasker Engine makes handling queuable multi-step tasks easy-ish'
  spec.license     = 'MIT'
  spec.required_ruby_version = Gem::Requirement.new('>= 3.2.0')

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/jcoletaylor/tasker'

  spec.files = Dir['{app,config,db,lib}/**/*', 'LICENSE', 'Rakefile', 'README.md', 'TODO.md']

  spec.add_dependency 'logger', '~> 1.6'
  spec.add_dependency 'rails', '~> 7.2.2'
  # Use postgresql as the database for Active Record
  spec.add_dependency 'pg', '~> 1.5'
  # Use Puma as the app server
  spec.add_dependency 'puma', '~> 6.6'

  spec.add_dependency 'sidekiq', '~> 7.3'

  # Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin AJAX possible
  spec.add_dependency 'active_model_serializers', '>= 0.10.0'
  spec.add_dependency 'ancestry', '~> 4.3.3'
  spec.add_dependency 'rack-cors'

  spec.add_dependency 'sorbet-runtime'

  spec.add_dependency 'json-schema', '>= 2.4.0'

  spec.add_dependency 'concurrent-ruby', '~> 1.3.5'
  spec.add_dependency 'concurrent-ruby-ext', '~> 1.3.5'
  spec.add_dependency 'dry-struct', '~> 1.8'
  spec.add_dependency 'dry-types', '~> 1.8'

  spec.add_dependency 'faraday', '~> 2.12.2'
  spec.add_dependency 'graphql'

  spec.metadata['rubygems_mfa_required'] = 'true'
end
