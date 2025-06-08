# frozen_string_literal: true

source 'https://rubygems.org'
ruby '3.2.4'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

# Specify your gem's dependencies in tasker.gemspec.
gemspec

# Security updates
gem 'concurrent-ruby', '~> 1.3.5', require: 'concurrent'
gem 'nokogiri', '~> 1.15.7'
gem 'rails-html-sanitizer', '>= 1.6.2'

group :development do
  gem 'byebug', '~> 11.1'
  gem 'listen', '~> 3.8'
  gem 'rswag-api', '~> 2.16'
  gem 'rswag-ui', '~> 2.16'
  gem 'rubocop', '~> 1.74', require: false
  gem 'rubocop-factory_bot', '~> 2.27', require: false
  gem 'rubocop-performance', '~> 1.24', require: false
  gem 'rubocop-rails', '~> 2.30', require: false
  gem 'rubocop-rake', '~> 0.7', require: false
  gem 'rubocop-rspec', '~> 2.31', require: false
end

group :test do
  gem 'rspec-json_expectations', '~> 2.2'
  gem 'rspec-rails', '~> 7.1'
  gem 'rspec-sidekiq', '~> 4.0'
  gem 'rswag-specs', '~> 2.16'
  gem 'simplecov', '~> 0.22', require: false
end

group :development, :test do
  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem 'brakeman', require: false
  gem 'dotenv-rails', '~> 2.8'
  gem 'factory_bot_rails', '~> 6.4'
  gem 'opentelemetry-instrumentation-all', '~> 0.74.0'
  gem 'rspec_junit_formatter', '~> 0.6.0' # For XML test output
  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem 'rubocop-rails-omakase', require: false
  gem 'sidekiq', '~> 7.3'
  gem 'yard', '~> 0.9'
end
