# typed: false
# frozen_string_literal: true

require_dependency 'tasker/application_controller'

module Tasker
  class GraphqlController < ApplicationController
    # If accessing from outside this domain, nullify the session
    # This allows for outside API access while preventing CSRF attacks,
    # but you'll have to authenticate your user separately
    # protect_from_forgery with: :null_session

    # Skip the standard controller authorization - we handle GraphQL authorization manually
    skip_before_action :authorize_tasker_action!, if: :authorization_enabled?

    def execute
      variables = prepare_variables(params[:variables])
      query = params[:query]
      operation_name = params[:operationName]

      # Authorize GraphQL operations before execution
      authorize_graphql_operations!(query, operation_name) if authorization_enabled?

      context = {
        # Query context goes here, for example:
        current_user: current_tasker_user,
        authenticated: tasker_user_authenticated?
      }
      result = Tasker::TaskerRailsSchema.execute(query, variables: variables, context: context,
                                                        operation_name: operation_name)
      render(json: result)
    rescue StandardError => e
      raise(e) unless Rails.env.development?

      handle_error_in_development(e)
    end

    private

    # Handle variables in form data, JSON body, or a blank value
    def prepare_variables(variables_param)
      case variables_param
      when String
        if variables_param.present?
          JSON.parse(variables_param) || {}
        else
          {}
        end
      when Hash
        variables_param
      when ActionController::Parameters
        variables_param.to_unsafe_hash # GraphQL-Ruby will validate name and type of incoming variables.
      when nil
        {}
      else
        raise(ArgumentError, "Unexpected parameter: #{variables_param}")
      end
    end

    def handle_error_in_development(e)
      logger.error(e.message)
      logger.error(e.backtrace.join("\n"))

      render(json: { errors: [{ message: e.message, backtrace: e.backtrace }], data: {} },
             status: :internal_server_error)
    end

    # Authorization methods for GraphQL operations

    def authorization_enabled?
      Tasker.configuration.auth.enabled
    end

    def authorize_graphql_operations!(query_string, operation_name)
      return if query_string.blank?

      # Parse the GraphQL query to extract operations
      operations = extract_graphql_operations(query_string, operation_name)

      # Check authorization for each operation
      operations.each do |operation|
        resource, action = map_graphql_operation_to_permission(operation)
        next unless resource && action

        authorization_coordinator.authorize!(resource, action, graphql_authorization_context(operation))
      end
    end

    def extract_graphql_operations(query_string, _operation_name)
      # Simple regex-based extraction of GraphQL operations
      # This is a basic implementation - for production, consider using GraphQL-Ruby's parser
      operations = []

      # Clean the query string
      query_string = query_string.strip

      # Determine if this is a query or mutation
      field_matches = query_string.scan(/{\s*(\w+)(?:\s*\([^)]*\))?\s*{/)
      if /^\s*mutation/i.match?(query_string)
        # Extract mutation fields
        # Pattern: mutation { mutationName(args) { ... } }
        field_matches.flatten.each do |field|
          operations << { type: :mutation, name: field.strip }
        end
      else
        # Default to query - extract query fields
        # Pattern: query { fieldName(args) { ... } } or { fieldName(args) { ... } }
        field_matches.flatten.each do |field|
          operations << { type: :query, name: field.strip }
        end
      end

      # Debug logging
      Rails.logger.debug { "GraphQL Query: #{query_string}" }
      Rails.logger.debug { "Extracted Operations: #{operations.inspect}" }

      operations
    end

    def map_graphql_operation_to_permission(operation)
      case operation[:type]
      when :query
        map_query_to_permission(operation[:name])
      when :mutation
        map_mutation_to_permission(operation[:name])
      else
        [nil, nil]
      end
    end

    def map_query_to_permission(query_name)
      case query_name
      when 'tasks', 'tasksByStatus', 'tasksByAnnotation'
        ['tasker.task', :index]
      when 'task'
        ['tasker.task', :show]
      when 'step'
        ['tasker.workflow_step', :show]
      when 'annotationTypes'
        # This might be a system-level query that doesn't need authorization
        [nil, nil]
      else
        # Unknown query - deny by default
        ['unknown.resource', :unknown]
      end
    end

    def map_mutation_to_permission(mutation_name)
      case mutation_name
      when 'createTask'
        ['tasker.task', :create]
      when 'updateTask'
        ['tasker.task', :update]
      when 'cancelTask'
        ['tasker.task', :cancel]
      when 'updateStep'
        ['tasker.workflow_step', :update]
      when 'cancelStep'
        ['tasker.workflow_step', :cancel]
      else
        # Unknown mutation - deny by default
        ['unknown.resource', :unknown]
      end
    end

    def authorization_coordinator
      @authorization_coordinator ||= build_authorization_coordinator
    end

    def build_authorization_coordinator
      coordinator_class = Tasker.configuration.auth.coordinator_class.constantize
      coordinator_class.new(current_tasker_user)
    rescue NameError => e
      raise Tasker::Authorization::ConfigurationError,
            "Authorization coordinator class '#{Tasker.configuration.auth.coordinator_class}' not found: #{e.message}"
    end

    def graphql_authorization_context(operation)
      {
        controller: self,
        params: params,
        graphql_operation: operation,
        user: current_tasker_user
      }
    end
  end
end
