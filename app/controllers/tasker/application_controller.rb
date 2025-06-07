# frozen_string_literal: true

# typed: false

module Tasker
  class ApplicationController < ActionController::API
    include Tasker::Concerns::Authenticatable

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
  end
end
