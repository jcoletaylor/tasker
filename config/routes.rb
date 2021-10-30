# frozen_string_literal: true

# typed: false
Tasker::Engine.routes.draw do
  post '/graphql', to: 'graphql#execute'
  resources :tasks do
    resources :workflow_steps
  end
end
