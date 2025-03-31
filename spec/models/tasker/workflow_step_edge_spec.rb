# frozen_string_literal: true

require 'rails_helper'
require_relative '../../helpers/task_helpers'

module Tasker
  RSpec.describe WorkflowStepEdge do
    let(:helper) { Helpers::TaskHelpers.new }
    let(:task_handler) { helper.factory.get(Helpers::TaskHelpers::DUMMY_TASK) }
    let(:task) { task_handler.initialize_task!(helper.task_request({ reason: 'edge relationship test' })) }
    let(:step_one) { task.get_step_by_name(DummyTask::STEP_ONE) }
    let(:step_two) { task.get_step_by_name(DummyTask::STEP_TWO) }
    let(:step_three) { task.get_step_by_name(DummyTask::STEP_THREE) }
    let(:step_four) { task.get_step_by_name(DummyTask::STEP_FOUR) }

    before do
      DependentSystem.find_or_create_by!(name: Helpers::TaskHelpers::DEPENDENT_SYSTEM)
      task.save!
    end

    describe 'associations' do
      it 'belongs to a from_step' do
        edge = described_class.create!(from_step: step_one, to_step: step_two, name: WorkflowStep::PROVIDES_EDGE_NAME)
        expect(edge.from_step).to eq(step_one)
      end

      it 'belongs to a to_step' do
        edge = described_class.create!(from_step: step_one, to_step: step_two, name: WorkflowStep::PROVIDES_EDGE_NAME)
        expect(edge.to_step).to eq(step_two)
      end
    end

    describe 'validations' do
      it 'requires a name' do
        edge = described_class.new(from_step: step_one, to_step: step_two)
        expect(edge).not_to be_valid
        expect(edge.errors[:name]).to include("can't be blank")
      end
    end

    describe 'scopes' do
      it 'finds children of a step' do
        described_class.create!(from_step: step_one, to_step: step_two, name: WorkflowStep::PROVIDES_EDGE_NAME)
        children = described_class.children_of(step_one)
        expect(children.count).to eq(1)
        expect(children.first.to_step).to eq(step_two)
      end

      it 'finds parents of a step' do
        described_class.create!(from_step: step_one, to_step: step_two, name: WorkflowStep::PROVIDES_EDGE_NAME)
        parents = described_class.parents_of(step_two)
        expect(parents.count).to eq(1)
        expect(parents.first.from_step).to eq(step_one)
      end

      describe 'siblings_of' do
        it 'finds steps that share one parent' do
          # create a relationship between step_one and step_two
          described_class.create!(from_step: step_one, to_step: step_two, name: WorkflowStep::PROVIDES_EDGE_NAME)

          # create a sibling from step_one to step_three, making step_two and step_three siblings
          described_class.create!(from_step: step_one, to_step: step_three, name: WorkflowStep::PROVIDES_EDGE_NAME)

          # create a sibling from step_two to step_four so that step_two and step_three are not siblings of step_four
          described_class.create!(from_step: step_two, to_step: step_four, name: WorkflowStep::PROVIDES_EDGE_NAME)

          # find the siblings of step_two
          siblings = described_class.siblings_of(step_two)
          expect(siblings.count).to eq(1)
          expect(siblings.first.to_step).to eq(step_three)
        end

        it 'finds steps that share all parents' do
          described_class.create!(from_step: step_one, to_step: step_two, name: WorkflowStep::PROVIDES_EDGE_NAME)
          described_class.create!(from_step: step_one, to_step: step_three, name: WorkflowStep::PROVIDES_EDGE_NAME)
          described_class.create!(from_step: step_four, to_step: step_two, name: WorkflowStep::PROVIDES_EDGE_NAME)
          described_class.create!(from_step: step_four, to_step: step_three, name: WorkflowStep::PROVIDES_EDGE_NAME)

          parents = described_class.parents_of(step_two)
          expect(parents.count).to eq(2)
          expect(parents.map(&:from_step)).to include(step_one, step_four)

          siblings = described_class.siblings_of(step_two)
          expect(siblings.count).to eq(2)
          expect(siblings.map(&:to_step)).to include(step_three)
        end

        it 'excludes the step itself from siblings' do
          described_class.create!(from_step: step_one, to_step: step_two, name: WorkflowStep::PROVIDES_EDGE_NAME)
          siblings = described_class.siblings_of(step_two)
          expect(siblings.map(&:to_step)).not_to include(step_two)
        end
      end
    end

    describe 'edge creation methods' do
      describe '#add_provides_edge!' do
        it 'creates a provides edge from one step to another' do
          step_one.add_provides_edge!(step_two)
          edge = described_class.last
          expect(edge.from_step).to eq(step_one)
          expect(edge.to_step).to eq(step_two)
          expect(edge.name).to eq(WorkflowStep::PROVIDES_EDGE_NAME)
        end
      end

      describe '#add_depends_on_edge!' do
        it 'creates a depends_on edge from one step to another' do
          step_two.add_depends_on_edge!(step_one)
          edge = described_class.last
          expect(edge.from_step).to eq(step_one)
          expect(edge.to_step).to eq(step_two)
          expect(edge.name).to eq(WorkflowStep::DEPENDS_ON_EDGE_NAME)
        end
      end
    end

    describe '.create_edge!' do
      it 'creates an edge with the given parameters' do
        edge = described_class.create_edge!(step_one, step_two, 'custom_edge')
        expect(edge.from_step).to eq(step_one)
        expect(edge.to_step).to eq(step_two)
        expect(edge.name).to eq('custom_edge')
      end
    end
  end
end
