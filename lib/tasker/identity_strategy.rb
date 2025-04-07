# frozen_string_literal: true

require 'securerandom'
require 'digest'

module Tasker
  # Base identity strategy class that generates a GUID by default
  class IdentityStrategy
    def generate_identity_hash(_task, _task_options)
      SecureRandom.uuid
    end
  end

  # Strategy that uses SHA256 hash of task identity options
  class HashIdentityStrategy < IdentityStrategy
    def generate_identity_hash(_task, task_options)
      Digest::SHA256.hexdigest(task_options.to_json)
    end
  end
end
