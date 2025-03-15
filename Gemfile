# frozen_string_literal: true

source 'https://rubygems.org'
ruby '3.2.7'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

# Specify your gem's dependencies in tasker.gemspec.
gemspec

# Security updates
gem 'nokogiri', '~> 1.15.7'
gem 'rails-html-sanitizer', '>= 1.6.2'
group :development do
  gem 'annotate', '~> 3.2'
  gem 'byebug', '~> 11.1'
  gem 'listen', '~> 3.8'
  gem 'rubocop', '~> 1.74', require: false
  gem 'rubocop-factory_bot', '~> 2.27', require: false
  gem 'rubocop-performance', '~> 1.24', require: false
  gem 'rubocop-rails', '~> 2.30', require: false
  gem 'rubocop-rspec', '~> 2.31', require: false
end

group :test do
  gem 'rspec-json_expectations', '~> 2.2'
  gem 'rspec-rails', '~> 7.1'
  gem 'rspec-sidekiq', '~> 4.0'
  gem 'rspec-sorbet', '~> 1.9'
  gem 'rswag-specs', '~> 2.16'
  gem 'simplecov', '~> 0.22', require: false
end

group :development, :test do
  gem 'dotenv-rails', '~> 2.8'
  gem 'sorbet', '~> 0.5.11934'
  gem 'sorbet-runtime', '~> 0.5.11934'
  gem 'sorbet-static', '~> 0.5.11934'
end
