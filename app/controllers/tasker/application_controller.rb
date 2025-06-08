# frozen_string_literal: true

# typed: false

module Tasker
  class ApplicationController < ActionController::API
    include Tasker::Concerns::Authenticatable
    include Tasker::Concerns::ControllerAuthorizable

    # Handle authentication errors with proper HTTP status codes
    rescue_from Tasker::Authentication::AuthenticationError do |exception|
      render json: { error: 'Unauthorized', message: exception.message }, status: :unauthorized
    end

    rescue_from Tasker::Authentication::ConfigurationError do |exception|
      render json: { error: 'Authentication Configuration Error', message: exception.message },
             status: :internal_server_error
    end

    rescue_from Tasker::Authentication::InterfaceError do |exception|
      render json: { error: 'Authentication Interface Error', message: exception.message },
             status: :internal_server_error
    end

    # Handle authorization errors with proper HTTP status codes
    rescue_from Tasker::Authorization::UnauthorizedError do |exception|
      render json: { error: 'Forbidden', message: exception.message }, status: :forbidden
    end

    rescue_from Tasker::Authorization::ConfigurationError do |exception|
      render json: { error: 'Authorization Configuration Error', message: exception.message },
             status: :internal_server_error
    end

    # Handle interface errors where coordinators don't implement required methods
    rescue_from NoMethodError do |exception|
      raise exception unless exception.message.include?('authorize!')

      render json: { error: 'Authorization Interface Error', message: 'Coordinator does not implement required authorize! method' },
             status: :internal_server_error
    end
  end
end
