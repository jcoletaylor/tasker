# typed: false
# frozen_string_literal: true

require 'rails_helper'
require_relative '../../mocks/dummy_task'

module Tasker
  RSpec.describe 'graphql annotation types', type: :request do
    before(:all) do
      @annotation_type = AnnotationType.find_or_create_by!(name: 'simple-test', description: 'simple test')
    end

    context 'queries' do
      it 'should get annotation types' do
        post '/tasker/graphql', params: { query: annotation_type_query }
        json = JSON.parse(response.body).deep_symbolize_keys
        data = json[:data][:annotationTypes]
        data.each do |annotation_type|
          expect(annotation_type[:annotationTypeId]).not_to be_nil
          expect(annotation_type[:name]).not_to be_nil
        end
        simple_type = data.find { |at| at[:annotationTypeId].to_i == @annotation_type.annotation_type_id }
        expect(simple_type[:name]).to eq(@annotation_type.name)
        expect(simple_type[:description]).to eq(@annotation_type.description)
      end
    end

    def annotation_type_query
      <<~GQL
        query GetAnnotationTypes {
          annotationTypes {
            annotationTypeId
            name
            description
          }
        }
      GQL
    end
  end
end
