# typed: false
# frozen_string_literal: true

require 'rails_helper'

module Tasker
  RSpec.describe WorkflowStepsController, type: :routing do
    describe 'routing' do
      it 'routes to #index' do
        expect(get: '/tasker/tasks/1/workflow_steps').to route_to('tasker/workflow_steps#index', task_id: '1')
      end

      it 'routes to #show' do
        expect(get: '/tasker/tasks/1/workflow_steps/1').to route_to('tasker/workflow_steps#show', task_id: '1', id: '1')
      end

      it 'routes to #create' do
        expect(post: '/tasker/tasks/1/workflow_steps').to route_to('tasker/workflow_steps#create', task_id: '1')
      end

      it 'routes to #update via PUT' do
        expect(put: '/tasker/tasks/1/workflow_steps/1').to route_to('tasker/workflow_steps#update', task_id: '1', id: '1')
      end

      it 'routes to #update via PATCH' do
        expect(patch: '/tasker/tasks/1/workflow_steps/1').to route_to('tasker/workflow_steps#update', task_id: '1', id: '1')
      end

      it 'routes to #destroy' do
        expect(delete: '/tasker/tasks/1/workflow_steps/1').to route_to('tasker/workflow_steps#destroy', task_id: '1', id: '1')
      end
    end
  end
end
