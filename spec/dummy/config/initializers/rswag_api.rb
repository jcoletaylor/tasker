# frozen_string_literal: true

if defined?(Rswag::Api)
  Rswag::Api.configure do |c|
    # Specify a root folder where OpenAPI files are located
    # This should match the swagger_helper.rb configuration
    c.openapi_root = Rails.root.join('swagger').to_s
  end
end
