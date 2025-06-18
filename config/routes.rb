# frozen_string_literal: true

# typed: false

Tasker::Engine.routes.draw do
  # Health check endpoints
  scope '/health', as: :health do
    get :ready, to: 'health#ready'
    get :live, to: 'health#live'
    get :status, to: 'health#status'
  end

  post '/graphql', to: 'graphql#execute'
  # mount Rswag::Ui::Engine => '/api-docs'
  # mount Rswag::Api::Engine => '/api-docs'
  resources :tasks do
    resources :workflow_steps
    resources :task_diagrams, only: %i[index]
  end
end
