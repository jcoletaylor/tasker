# typed: false
# frozen_string_literal: true

module Tasker
  class HandlerSerializer < ActiveModel::Serializer
    attributes :name, :namespace, :version, :full_name, :class_name, :available, :step_templates

    def initialize(object, options = {})
      @handler_name = options[:handler_name]
      @namespace = options[:namespace] || :default
      @version = options[:version] || '0.1.0'
      @handler_class = object
      super
    end

    def name
      @handler_name.to_s
    end

    def namespace
      @namespace.to_s
    end

    def version
      @version.to_s
    end

    def full_name
      "#{namespace}.#{name}@#{version}"
    end

    def class_name
      if @handler_class.is_a?(Class)
        @handler_class.name
      else
        @handler_class.to_s
      end
    end

    def available
      instantiate_handler
      true
    rescue StandardError
      false
    end

    def step_templates
      return [] unless handler_instance

      begin
        templates = handler_instance.step_templates
        return [] unless templates.respond_to?(:map)

        templates.map do |template|
          template_hash = {}

          # Handle StepTemplate dry-struct attributes
          template_hash[:name] = template.name.to_s if template.respond_to?(:name)
          template_hash[:description] = template.description if template.respond_to?(:description)
          template_hash[:dependent_system] = template.dependent_system.to_s if template.respond_to?(:dependent_system)
          if template.respond_to?(:depends_on_step) && template.depends_on_step
            template_hash[:depends_on_step] =
              template.depends_on_step.to_s
          end
          template_hash[:depends_on_steps] = template.depends_on_steps if template.respond_to?(:depends_on_steps)

          # Handle handler class - could be Class object or string
          if template.respond_to?(:handler_class)
            template_hash[:handler_class] =
              template.handler_class.is_a?(Class) ? template.handler_class.name : template.handler_class.to_s
          end

          # Use the correct attribute name for configuration
          template_hash[:configuration] = template.handler_config if template.respond_to?(:handler_config)

          # Include dry-struct specific attributes
          template_hash[:default_retryable] = template.default_retryable if template.respond_to?(:default_retryable)
          if template.respond_to?(:default_retry_limit)
            template_hash[:default_retry_limit] =
              template.default_retry_limit
          end
          template_hash[:skippable] = template.skippable if template.respond_to?(:skippable)
          template_hash[:custom_events] = template.custom_events if template.respond_to?(:custom_events)

          template_hash
        end
      rescue StandardError => e
        Rails.logger.warn "Failed to introspect step templates for #{class_name}: #{e.message}"
        []
      end
    end

    private

    def handler_instance
      @handler_instance ||= instantiate_handler
    rescue StandardError
      nil
    end

    def instantiate_handler
      if @handler_class.is_a?(Class)
        @handler_class.new
      else
        @handler_class.to_s.camelize.constantize.new
      end
    end
  end
end
