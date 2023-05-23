# typed: false
# frozen_string_literal: true

# == Schema Information
#
# Table name: dependent_system_object_maps
#
#  remote_id_one                  :string(128)      not null
#  remote_id_two                  :string(128)      not null
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  dependent_system_object_map_id :bigint           not null, primary key
#  dependent_system_one_id        :integer          not null
#  dependent_system_two_id        :integer          not null
#
# Indexes
#
#  dependent_system_object_maps_dependent_system_one_id_dependent_  (dependent_system_one_id,dependent_system_two_id,remote_id_one,remote_id_two) UNIQUE
#  dependent_system_object_maps_dependent_system_one_id_index       (dependent_system_one_id)
#  dependent_system_object_maps_dependent_system_two_id_index       (dependent_system_two_id)
#  dependent_system_object_maps_remote_id_one_index                 (remote_id_one)
#  dependent_system_object_maps_remote_id_two_index                 (remote_id_two)
#
# Foreign Keys
#
#  dependent_system_object_maps_dependent_system_one_id_foreign  (dependent_system_one_id => dependent_systems.dependent_system_id)
#  dependent_system_object_maps_dependent_system_two_id_foreign  (dependent_system_two_id => dependent_systems.dependent_system_id)
#
require 'rails_helper'

module Tasker
  RSpec.describe DependentSystemObjectMap do
    describe 'find or create' do
      it 'is able to find or create in either order' do
        system_name_one = 'first_system'
        system_name_two = 'second_system'
        system_one_id = 'asdgasdfasdfsadf'
        system_two_id = 3
        system_mapping = described_class.find_or_create(
          system_name_one, system_one_id,
          system_name_two, system_two_id
        )

        expect(system_mapping.dependent_system_object_map_id).not_to be_nil
        system_mapping_two = described_class.find_or_create(
          system_name_two, system_two_id,
          system_name_one, system_one_id
        )
        expect(system_mapping_two.dependent_system_object_map_id).to eq(system_mapping.dependent_system_object_map_id)
      end
    end
  end
end
