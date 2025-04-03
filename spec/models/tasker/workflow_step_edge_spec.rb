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
    let(:edge) do
      described_class.create!(
        from_step: step_one,
        to_step: step_two,
        name: WorkflowStep::PROVIDES_EDGE_NAME
      )
    end

    let(:edge_two) do
      described_class.create!(
        from_step: step_two,
        to_step: step_three,
        name: WorkflowStep::PROVIDES_EDGE_NAME
      )
    end

    let(:edge_cycle) do
      described_class.create!(
        from_step: step_two,
        to_step: step_one,
        name: WorkflowStep::PROVIDES_EDGE_NAME
      )
    end

    let(:edge_cycle_two) do
      described_class.create!(
        from_step: step_three,
        to_step: step_one,
        name: WorkflowStep::PROVIDES_EDGE_NAME
      )
    end

    before do
      DependentSystem.find_or_create_by!(name: Helpers::TaskHelpers::DEPENDENT_SYSTEM)
      task.save!
    end

    describe 'associations' do
      it 'belongs to a from_step' do
        expect(edge.from_step).to eq(step_one)
      end

      it 'belongs to a to_step' do
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

    describe 'cycle prevention' do
      it 'allows a simple edge' do
        expect(edge).to be_persisted
      end

      it 'prevents direct cycles' do
        edge
        # Attempt to create a cycle
        expect do
          edge_cycle
        end.to raise_error(ActiveRecord::RecordInvalid, 'Adding this edge would create a cycle in the workflow')
      end

      it 'prevents indirect cycles' do
        # Create a chain: step_one -> step_two -> step_three
        edge
        edge_two

        # Attempt to create a cycle: step_three -> step_one
        expect do
          edge_cycle_two
        end.to raise_error(ActiveRecord::RecordInvalid, 'Adding this edge would create a cycle in the workflow')
      end

      it 'allows multiple paths to the same destination' do
        # First, delete any existing edges from the setup to start with a clean graph
        described_class.delete_all

        # Create two paths to step_three: step_one -> step_three and step_two -> step_three
        edge1 = described_class.create!(from_step: step_one, to_step: step_three,
                                        name: WorkflowStep::PROVIDES_EDGE_NAME)
        edge2 = described_class.create!(from_step: step_two, to_step: step_three,
                                        name: WorkflowStep::PROVIDES_EDGE_NAME)

        expect(edge1).to be_persisted
        expect(edge2).to be_persisted

        # Create a path from step_four to step_three (should be valid as it doesn't create a cycle)
        edge3 = described_class.create!(from_step: step_four, to_step: step_three,
                                        name: WorkflowStep::PROVIDES_EDGE_NAME)
        expect(edge3).to be_persisted
      end
    end

    describe 'scopes' do
      it 'finds children of a step' do
        edge
        children = described_class.children_of(step_one)
        expect(children.count).to eq(1)
        expect(children.first.to_step).to eq(step_two)
      end

      it 'finds parents of a step' do
        edge
        parents = described_class.parents_of(step_two)
        expect(parents.count).to eq(1)
        expect(parents.first.from_step).to eq(step_one)
      end

      describe 'siblings_of' do
        it 'finds steps that share one parent' do
          # Delete any existing edges
          described_class.delete_all

          # Create a simple structure where step_one is a parent to both step_two and step_three
          described_class.create!(from_step: step_one, to_step: step_two,
                                  name: WorkflowStep::PROVIDES_EDGE_NAME)
          described_class.create!(from_step: step_one, to_step: step_three,
                                  name: WorkflowStep::PROVIDES_EDGE_NAME)

          # Step_two has step_four as a child (to avoid cycles)
          described_class.create!(from_step: step_two, to_step: step_four, name: WorkflowStep::PROVIDES_EDGE_NAME)

          # Find the siblings of step_two
          siblings = described_class.siblings_of(step_two)
          expect(siblings.count).to eq(1)
          expect(siblings.first.to_step).to eq(step_three)
        end

        it 'finds steps that share all parents' do
          # Delete any existing edges to start with a clean graph
          described_class.delete_all

          # Create a structure where step_two and step_three share multiple parents
          described_class.create!(from_step: step_one, to_step: step_two, name: WorkflowStep::PROVIDES_EDGE_NAME)
          described_class.create!(from_step: step_one, to_step: step_three, name: WorkflowStep::PROVIDES_EDGE_NAME)
          described_class.create!(from_step: step_four, to_step: step_two, name: WorkflowStep::PROVIDES_EDGE_NAME)
          described_class.create!(from_step: step_four, to_step: step_three, name: WorkflowStep::PROVIDES_EDGE_NAME)

          # Verify the parent relationships
          parents = described_class.parents_of(step_two)
          expect(parents.count).to eq(2)
          expect(parents.map(&:from_step)).to include(step_one, step_four)

          # Check siblings
          # The siblings_of method returns the edges to sibling steps, one edge per parent
          # Since we have two parents (step_one and step_four) and one sibling step (step_three),
          # we expect two edges (step_one -> step_three and step_four -> step_three)
          siblings = described_class.siblings_of(step_two)
          expect(siblings.count).to eq(2)
          expect(siblings.map(&:from_step)).to include(step_one, step_four)
          expect(siblings.map(&:to_step).uniq).to eq([step_three])
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
