# typed: strict
# frozen_string_literal: true

Rails.application.routes.draw do
  mount Tasker::Engine => '/tasker', as: 'tasker'
end
