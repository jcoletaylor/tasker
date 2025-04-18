# typed: false
# frozen_string_literal: true

require 'rails_helper'

module Tasker
  RSpec.describe(TaskDiagramsController) do
    describe 'routing' do
      it 'routes to #index' do
        expect(get: '/tasker/tasks/1/task_diagrams').to(route_to('tasker/task_diagrams#index', task_id: '1'))
      end
    end
  end
end
