# frozen_string_literal: true

require 'yaml'

module Tasker
  module Events
    # SubscriptionLoader loads event subscriptions from YAML configuration files
    #
    # This class enables developers to configure event subscriptions declaratively
    # using YAML files in config/tasker/subscriptions/
    #
    # Example YAML structure:
    #   subscriptions:
    #     sentry_integration:
    #       class: 'SentrySubscriber'
    #       events:
    #         - 'task.failed'
    #         - 'step.failed'
    #       config:
    #         dsn: 'https://...'
    #         environment: 'production'
    #
    class SubscriptionLoader
      class << self
        # Load all subscription configurations from YAML files
        #
        # @return [Hash] Loaded subscription configurations
        def load_all
          @load_all ||= load_subscription_files
        end

        # Load and instantiate all configured subscribers
        #
        # @return [Array<BaseSubscriber>] Array of instantiated subscribers
        def load_subscribers
          subscribers = []

          load_all.each do |name, config|
            subscriber = instantiate_subscriber(name, config)
            subscribers << subscriber if subscriber
          rescue StandardError => e
            Rails.logger.warn "Failed to load subscriber #{name}: #{e.message}"
          end

          subscribers
        end

        # Register all loaded subscribers with the event system
        #
        # @return [void]
        def register_all_subscribers
          load_subscribers.each do |subscriber|
            Rails.logger.info "Registering subscriber: #{subscriber.class.name}"
            # Subscribers auto-register themselves when instantiated
          end
        end

        # Reload subscription configurations (useful for development)
        #
        # @return [Hash] Reloaded subscription configurations
        def reload!
          @loaded_subscriptions = nil
          load_all
        end

        private

        # Load subscription configurations from all YAML files
        #
        # @return [Hash] Combined subscription configurations
        def load_subscription_files
          subscriptions = {}

          subscription_files.each do |file_path|
            file_subscriptions = load_subscription_file(file_path)
            subscriptions.merge!(file_subscriptions)
          rescue StandardError => e
            Rails.logger.warn "Failed to load subscription file #{file_path}: #{e.message}"
          end

          subscriptions
        end

        # Load subscription configuration from a single YAML file
        #
        # @param file_path [String] Path to the YAML file
        # @return [Hash] Subscription configurations from the file
        def load_subscription_file(file_path)
          yaml_data = YAML.load_file(file_path)
          subscriptions_data = yaml_data['subscriptions'] || {}

          # Validate and normalize subscription configurations
          normalized = {}
          subscriptions_data.each do |name, config|
            normalized[name] = normalize_subscription_config(name, config)
          end

          normalized
        end

        # Normalize and validate a subscription configuration
        #
        # @param name [String] Subscription name
        # @param config [Hash] Raw subscription configuration
        # @return [Hash] Normalized subscription configuration
        def normalize_subscription_config(name, config)
          {
            name: name,
            class: config['class'] || config[:class],
            events: Array(config['events'] || config[:events]),
            config: config['config'] || config[:config] || {},
            enabled: config.fetch('enabled', config.fetch(:enabled, true))
          }
        end

        # Instantiate a subscriber from configuration
        #
        # @param name [String] Subscription name
        # @param config [Hash] Subscription configuration
        # @return [BaseSubscriber, nil] Instantiated subscriber or nil if disabled/failed
        def instantiate_subscriber(_name, config)
          return nil unless config[:enabled]

          subscriber_class = resolve_subscriber_class(config[:class])
          return nil unless subscriber_class

          # Pass configuration to subscriber constructor
          subscriber_class.new(
            name: config[:name],
            events: config[:events],
            config: config[:config]
          )
        end

        # Resolve subscriber class from string name
        #
        # @param class_name [String] Class name to resolve
        # @return [Class, nil] Resolved class or nil if not found
        def resolve_subscriber_class(class_name)
          return nil unless class_name

          # Try to constantize the class name
          class_name.constantize
        rescue NameError => e
          Rails.logger.warn "Subscriber class not found: #{class_name} (#{e.message})"
          nil
        end

        # Get all subscription YAML files
        #
        # @return [Array<String>] Array of file paths
        def subscription_files
          subscription_dir = Rails.root.join('config/tasker/subscriptions')
          return [] unless subscription_dir.exist?

          Dir.glob(subscription_dir.join('*.yml'))
        end
      end
    end
  end
end
