# typed: false
# frozen_string_literal: true

Rails.application.routes.draw do
  # Mount Rswag engines in dummy app (only when gems are available)
  if defined?(Rswag::Api) && defined?(Rswag::Ui)
    mount Rswag::Api::Engine => '/tasker/api-docs'
    mount Rswag::Ui::Engine => '/tasker/api-docs'
  end
  mount Tasker::Engine => '/tasker', as: 'tasker'
end
