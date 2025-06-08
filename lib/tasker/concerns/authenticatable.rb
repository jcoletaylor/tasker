# frozen_string_literal: true

require_relative '../authentication/coordinator'

module Tasker
  module Concerns
    module Authenticatable
      extend ActiveSupport::Concern

      included do
        before_action :authenticate_tasker_user!, unless: :skip_authentication?
      end

      private

      def authenticate_tasker_user!
        return true if skip_authentication?

        Tasker::Authentication::Coordinator.authenticate!(self)
      rescue Tasker::Authentication::AuthenticationError => e
        # Only render response if we're in a real controller context
        # In unit tests, let the exception bubble up for testing
        raise unless respond_to?(:render) && respond_to?(:request)

        render json: { error: 'Unauthorized', message: e.message }, status: :unauthorized
      end

      def current_tasker_user
        @current_tasker_user ||= Tasker::Authentication::Coordinator.current_user(self)
      end

      def tasker_user_authenticated?
        Tasker::Authentication::Coordinator.authenticated?(self)
      end

      def skip_authentication?
        !Tasker.configuration.auth.authentication_enabled
      end
    end
  end
end
