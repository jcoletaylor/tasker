# typed: false
# frozen_string_literal: true

require 'rails_helper'

module Tasker
  RSpec.describe TasksController, type: :routing do
    describe 'routing' do
      it 'routes to #index' do
        expect(get: '/tasker/tasks').to route_to('tasker/tasks#index')
      end

      it 'routes to #show' do
        expect(get: '/tasker/tasks/1').to route_to('tasker/tasks#show', id: '1')
      end

      it 'routes to #create' do
        expect(post: '/tasker/tasks').to route_to('tasker/tasks#create')
      end

      it 'routes to #update via PUT' do
        expect(put: '/tasker/tasks/1').to route_to('tasker/tasks#update', id: '1')
      end

      it 'routes to #update via PATCH' do
        expect(patch: '/tasker/tasks/1').to route_to('tasker/tasks#update', id: '1')
      end

      it 'routes to #destroy' do
        expect(delete: '/tasker/tasks/1').to route_to('tasker/tasks#destroy', id: '1')
      end
    end
  end
end
