# frozen_string_literal: true

# typed: false

Tasker::Engine.routes.draw do
  # Health check endpoints
  scope '/health', as: :health do
    get :ready, to: 'health#ready'
    get :live, to: 'health#live'
    get :status, to: 'health#status'
  end

  # Metrics endpoint
  get '/metrics', to: 'metrics#index'

  # Analytics endpoints
  scope '/analytics', as: :analytics do
    get :performance, to: 'analytics#performance'
    get :bottlenecks, to: 'analytics#bottlenecks'
  end

  # Handler discovery endpoints
  get '/handlers', to: 'handlers#index' # List namespaces
  get '/handlers/:namespace', to: 'handlers#show_namespace' # List handlers in namespace
  get '/handlers/:namespace/:name', to: 'handlers#show'     # Show specific handler with dependency graph

  # GraphQL endpoint
  post '/graphql', to: 'graphql#execute'

  # Task endpoints
  resources :tasks do
    resources :workflow_steps
  end
end
