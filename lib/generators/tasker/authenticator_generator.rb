# frozen_string_literal: true

require 'rails/generators'

module Tasker
  module Generators
    class AuthenticatorGenerator < Rails::Generators::NamedBase
      source_root File.expand_path('templates', __dir__)

      desc 'Generate a new Tasker authenticator class with configuration validation and tests'

      class_option :type, type: :string, default: 'custom',
                          desc: 'Type of authenticator (custom, devise, jwt, api_token, omniauth)'

      class_option :directory, type: :string, default: 'app/tasker/authenticators',
                               desc: 'Directory to place the authenticator'

      class_option :user_class, type: :string, default: 'User',
                                desc: 'User model class name'

      class_option :with_spec, type: :boolean, default: true,
                               desc: 'Generate spec file'

      def create_authenticator_file
        ensure_directory_exists(options[:directory])

        case options[:type].downcase
        when 'jwt'
          template 'jwt_authenticator.rb.erb', File.join(options[:directory], "#{file_name}_authenticator.rb")
        when 'devise'
          template 'devise_authenticator.rb.erb', File.join(options[:directory], "#{file_name}_authenticator.rb")
        when 'api_token'
          template 'api_token_authenticator.rb.erb', File.join(options[:directory], "#{file_name}_authenticator.rb")
        when 'omniauth'
          template 'omniauth_authenticator.rb.erb', File.join(options[:directory], "#{file_name}_authenticator.rb")
        else
          template 'custom_authenticator.rb.erb', File.join(options[:directory], "#{file_name}_authenticator.rb")
        end
      end

      def create_spec_file
        return unless options[:with_spec] && defined?(RSpec)

        ensure_directory_exists('spec/tasker/authenticators')

        case options[:type].downcase
        when 'jwt'
          template 'jwt_authenticator_spec.rb.erb',
                   File.join('spec/tasker/authenticators', "#{file_name}_authenticator_spec.rb")
        when 'devise'
          template 'devise_authenticator_spec.rb.erb',
                   File.join('spec/tasker/authenticators', "#{file_name}_authenticator_spec.rb")
        when 'api_token'
          template 'api_token_authenticator_spec.rb.erb',
                   File.join('spec/tasker/authenticators', "#{file_name}_authenticator_spec.rb")
        when 'omniauth'
          template 'omniauth_authenticator_spec.rb.erb',
                   File.join('spec/tasker/authenticators', "#{file_name}_authenticator_spec.rb")
        else
          template 'custom_authenticator_spec.rb.erb',
                   File.join('spec/tasker/authenticators', "#{file_name}_authenticator_spec.rb")
        end
      end

      def show_usage_instructions
        UsageInstructionsFormatter.display(self)
      end

      # Service class to format and display usage instructions
      # Reduces complexity by organizing instruction display logic
      class UsageInstructionsFormatter
        class << self
          # Display complete usage instructions for the generator
          #
          # @param generator [AuthenticatorGenerator] The generator instance
          # @return [void]
          def display(generator)
            display_success_header(generator)
            display_created_files(generator)
            display_configuration_example(generator)
            display_type_specific_instructions(generator)
            display_test_instructions(generator)
            display_documentation_links(generator)
          end

          private

          # Display success header
          #
          # @param generator [AuthenticatorGenerator] The generator instance
          # @return [void]
          def display_success_header(generator)
            generator.say "\n#{generator.set_color('Authenticator created successfully!', :green)}"
          end

          # Display list of created files
          #
          # @param generator [AuthenticatorGenerator] The generator instance
          # @return [void]
          def display_created_files(generator)
            generator.say "\n#{generator.set_color('Files created:', :cyan)}"
            generator.say "  - #{File.join(generator.options[:directory],
                                           "#{generator.send(:file_name)}_authenticator.rb")}"

            return unless generator.options[:with_spec] && defined?(RSpec)

            generator.say "  - #{File.join('spec/tasker/authenticators',
                                           "#{generator.send(:file_name)}_authenticator_spec.rb")}"
          end

          # Display configuration example
          #
          # @param generator [AuthenticatorGenerator] The generator instance
          # @return [void]
          def display_configuration_example(generator)
            generator.say "\n#{generator.set_color('Configuration example:', :yellow)}"
            generator.say generator.send(:configuration_example)
          end

          # Display type-specific next steps
          #
          # @param generator [AuthenticatorGenerator] The generator instance
          # @return [void]
          def display_type_specific_instructions(generator)
            generator.say "\n#{generator.set_color('Next steps:', :cyan)}"

            case generator.options[:type].downcase
            when 'jwt'
              generator.send(:show_jwt_instructions)
            when 'devise'
              generator.send(:show_devise_instructions)
            when 'api_token'
              generator.send(:show_api_token_instructions)
            when 'omniauth'
              generator.send(:show_omniauth_instructions)
            else
              generator.send(:show_custom_instructions)
            end
          end

          # Display test running instructions
          #
          # @param generator [AuthenticatorGenerator] The generator instance
          # @return [void]
          def display_test_instructions(generator)
            return unless generator.options[:with_spec] && defined?(RSpec)

            generator.say "\n  4. Run your tests:"
            generator.say "     bundle exec rspec spec/tasker/authenticators/#{generator.send(:file_name)}_authenticator_spec.rb"
          end

          # Display documentation links
          #
          # @param generator [AuthenticatorGenerator] The generator instance
          # @return [void]
          def display_documentation_links(generator)
            generator.say "\n#{generator.set_color('Documentation:', :magenta)}"
            generator.say '  See docs/AUTH.md for complete authentication guide'
          end
        end
      end

      private

      def file_name
        @file_name ||= name.underscore
      end

      def class_name
        @class_name ||= name.camelize
      end

      def user_model_class
        options[:user_class]
      end

      def authenticator_type
        options[:type].downcase
      end

      def ensure_directory_exists(directory)
        directory_path = Rails.root.join(directory)
        return if File.directory?(directory_path)

        FileUtils.mkdir_p(directory_path)
        say "Created directory: #{directory_path}"
      end

      def configuration_example
        case authenticator_type
        when 'jwt'
          jwt_config_example
        when 'devise'
          devise_config_example
        when 'api_token'
          api_token_config_example
        when 'omniauth'
          omniauth_config_example
        else
          custom_config_example
        end
      end

      def jwt_config_example
        <<~CONFIG
          # config/initializers/tasker.rb
          Tasker.configuration do |config|
            config.auth do |auth|
              auth.authentication_enabled = true
              auth.authenticator_class = '#{class_name}Authenticator'
              auth.user_class = '#{user_model_class}'
            end
          end
        CONFIG
      end

      def devise_config_example
        <<~CONFIG
          # config/initializers/tasker.rb
          Tasker.configuration do |config|
            config.auth do |auth|
              auth.authentication_enabled = true
              auth.authenticator_class = '#{class_name}Authenticator'
              auth.user_class = '#{user_model_class}'
            end
          end
        CONFIG
      end

      def api_token_config_example
        <<~CONFIG
          # config/initializers/tasker.rb
          Tasker.configuration do |config|
            config.auth do |auth|
              auth.authentication_enabled = true
              auth.authenticator_class = '#{class_name}Authenticator'
              auth.user_class = '#{user_model_class}'
            end
          end
        CONFIG
      end

      def omniauth_config_example
        <<~CONFIG
          # config/initializers/tasker.rb
          Tasker.configuration do |config|
            config.auth do |auth|
              auth.authentication_enabled = true
              auth.authenticator_class = '#{class_name}Authenticator'
              auth.user_class = '#{user_model_class}'
            end
          end
        CONFIG
      end

      def custom_config_example
        <<~CONFIG
          # config/initializers/tasker.rb
          Tasker.configuration do |config|
            config.auth do |auth|
              auth.authentication_enabled = true
              auth.authenticator_class = '#{class_name}Authenticator'
              auth.user_class = '#{user_model_class}'
              # Add your custom configuration here
            end
          end
        CONFIG
      end

      def show_jwt_instructions
        say '  1. Add jwt gem to your Gemfile: gem "jwt"'
        say '  2. Set JWT secret in Rails credentials or environment variables'
        say "  3. Customize token extraction and user lookup logic in #{class_name}Authenticator"
      end

      def show_devise_instructions
        say '  1. Ensure Devise is properly configured in your application'
        say '  2. Verify the authentication scope matches your Devise configuration'
        say "  3. Customize authentication logic in #{class_name}Authenticator if needed"
      end

      def show_api_token_instructions
        say "  1. Add api_token column to your #{user_model_class} model"
        say '  2. Implement token generation and validation in your user model'
        say "  3. Customize token extraction logic in #{class_name}Authenticator"
      end

      def show_omniauth_instructions
        say '  1. Ensure OmniAuth is properly configured'
        say "  2. Implement provider-based user lookup in your #{user_model_class} model"
        say "  3. Customize authentication flow in #{class_name}Authenticator"
      end

      def show_custom_instructions
        say "  1. Implement your authentication logic in #{class_name}Authenticator"
        say '  2. Add any required gems or dependencies'
        say '  3. Update configuration options as needed'
      end
    end
  end
end
