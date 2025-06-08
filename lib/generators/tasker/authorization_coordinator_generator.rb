# frozen_string_literal: true

require 'rails/generators'

module Tasker
  module Generators
    # Rails generator for creating authorization coordinators
    #
    # This generator creates authorization coordinator classes that inherit from
    # Tasker::Authorization::BaseCoordinator and implement the authorization
    # interface for different scenarios.
    #
    # @example Basic usage
    #   rails generate tasker:authorization_coordinator CompanyAuth
    #   rails generate tasker:authorization_coordinator TeamAuth --user-class=Team
    #
    class AuthorizationCoordinatorGenerator < Rails::Generators::NamedBase
      source_root File.expand_path('templates', __dir__)

      desc 'Generate a Tasker authorization coordinator class'

      class_option :user_class,
                   type: :string,
                   default: 'User',
                   desc: 'User model class name'

      class_option :directory,
                   type: :string,
                   default: 'app/tasker/authorization',
                   desc: 'Directory to create the coordinator in'

      class_option :with_spec,
                   type: :boolean,
                   default: true,
                   desc: 'Generate spec file'

      # Generate the authorization coordinator class
      def create_coordinator_class
        @coordinator_class_name = coordinator_class_name
        @user_class_name = user_class_name

        template 'authorization_coordinator.rb.erb',
                 File.join(options[:directory], "#{file_name}_coordinator.rb")
      end

      # Generate the spec file if requested
      def create_spec_file
        return unless options[:with_spec]

        @coordinator_class_name = coordinator_class_name
        @user_class_name = user_class_name

        template 'authorization_coordinator_spec.rb.erb',
                 File.join('spec', options[:directory].sub('app/', ''), "#{file_name}_coordinator_spec.rb")
      end

      # Print usage instructions
      def print_instructions
        say "\n#{set_color('Authorization Coordinator Generated!', :green)}"
        say set_color('=' * 50, :green)

        say "\nGenerated files:"
        say "  #{set_color("#{options[:directory]}/#{file_name}_coordinator.rb", :cyan)} - Coordinator class"
        if options[:with_spec]
          say "  #{set_color("spec/#{options[:directory].sub('app/', '')}/#{file_name}_coordinator_spec.rb",
                             :cyan)} - Test file"
        end

        say "\nNext steps:"
        say '1. Configure Tasker to use your coordinator:'
        say coordinator_configuration_example

        say "\n2. Ensure your User model includes the Authorizable concern:"
        say user_model_example

        say "\n3. Customize the authorization logic in your coordinator"
        say "\n4. Run the tests to verify everything works:"
        say "   #{set_color(
          "bundle exec rspec spec/#{options[:directory].sub('app/', '')}/#{file_name}_coordinator_spec.rb", :yellow
        )}"

        say "\nFor more information, see the Tasker authentication guide:"
        say "  #{set_color('docs/AUTH.md', :cyan)}"
      end

      private

      # Get the coordinator class name
      def coordinator_class_name
        "#{class_name}Coordinator"
      end

      # Get the user class name
      def user_class_name
        options[:user_class]
      end

      # Generate configuration example
      def coordinator_configuration_example
        <<~CONFIG

          ```ruby
          # config/initializers/tasker.rb
          Tasker.configuration do |config|
            config.auth do |auth|
              auth.authorization_enabled = true
              auth.authorization_coordinator_class = '#{coordinator_class_name}'
              auth.user_class = '#{user_class_name}'
            end
          end
          ```
        CONFIG
      end

      # Generate user model example
      def user_model_example
        <<~USER_MODEL

          ```ruby
          # app/models/#{user_class_name.underscore}.rb
          class #{user_class_name} < ApplicationRecord
            include Tasker::Concerns::Authorizable

            def has_tasker_permission?(permission)
              # Your permission checking logic
              permissions.include?(permission)
            end

            def tasker_admin?
              # Your admin checking logic
              role == 'admin' || roles.include?('admin')
            end
          end
          ```
        USER_MODEL
      end
    end
  end
end
