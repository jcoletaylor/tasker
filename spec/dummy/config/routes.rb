# typed: false
# frozen_string_literal: true

Rails.application.routes.draw do
  # mount Rswag::Ui::Engine => '/tasker/api-docs'
  # mount Rswag::Api::Engine => '/tasker/api-docs'
  mount Tasker::Engine => '/tasker', as: 'tasker'
end
