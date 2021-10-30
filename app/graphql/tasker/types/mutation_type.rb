# typed: true
# frozen_string_literal: true

module Tasker
  module Types
    class MutationType < Types::BaseObject
      # TODO: remove me
      field :ping, String, null: false, description: 'Ping-Pong'
      def ping
        'pong'
      end
    end
  end
end
