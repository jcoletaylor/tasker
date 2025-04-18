# frozen_string_literal: true

# typed: false

Tasker::Engine.routes.draw do
  post '/graphql', to: 'graphql#execute'
  # mount Rswag::Ui::Engine => '/api-docs'
  # mount Rswag::Api::Engine => '/api-docs'
  resources :tasks do
    resources :workflow_steps
    resources :task_diagrams, only: %i[index]
  end
end
