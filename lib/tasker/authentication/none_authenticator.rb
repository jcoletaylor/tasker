# frozen_string_literal: true

require_relative 'interface'

module Tasker
  module Authentication
    class NoneAuthenticator
      include Interface

      def authenticate!(_controller)
        # No authentication required - always succeeds
        true
      end

      def current_user(_controller)
        # No user in no-auth mode
        nil
      end

      def authenticated?(_controller)
        # Always considered "authenticated" in no-auth mode
        true
      end
    end
  end
end
