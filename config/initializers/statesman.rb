# frozen_string_literal: true

# Configure Statesman to use ActiveRecord adapter for persistence
Statesman.configure do
  storage_adapter(Statesman::Adapters::ActiveRecord)
end
