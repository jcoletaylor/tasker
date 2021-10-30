# typed: strict
# frozen_string_literal: true

# == Schema Information
#
# Table name: task_annotations
#
#  annotation         :jsonb
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  annotation_type_id :integer          not null
#  task_annotation_id :bigint           not null, primary key
#  task_id            :bigint           not null
#
# Indexes
#
#  task_annotations_annotation_idx            (annotation) USING gin
#  task_annotations_annotation_idx1           (annotation) USING gin
#  task_annotations_annotation_type_id_index  (annotation_type_id)
#  task_annotations_task_id_index             (task_id)
#
# Foreign Keys
#
#  task_annotations_annotation_type_id_foreign  (annotation_type_id => annotation_types.annotation_type_id)
#  task_annotations_task_id_foreign             (task_id => tasks.task_id)
#

module Tasker
  class TaskAnnotationSerializer < ActiveModel::Serializer
    attributes :task_id, :task_annotation_id, :annotation, :annotation_type_name
  end
end
