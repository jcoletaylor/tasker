# frozen_string_literal: true

if defined?(Rswag::Ui)
  Rswag::Ui.configure do |c|
    # List the OpenAPI endpoints for the swagger-ui dropdown
    # This tells the UI where to find the API documentation
    c.openapi_endpoint '/tasker/api-docs/v1/swagger.yaml', 'Tasker API V1'
  end
end
