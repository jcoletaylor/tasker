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
      end

      def current_tasker_user
        @current_tasker_user ||= Tasker::Authentication::Coordinator.current_user(self)
      end

      def tasker_user_authenticated?
        Tasker::Authentication::Coordinator.authenticated?(self)
      end

      def skip_authentication?
        Tasker.configuration.auth.strategy == :none
      end
    end
  end
end
