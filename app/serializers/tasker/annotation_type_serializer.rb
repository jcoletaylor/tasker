# typed: false
# frozen_string_literal: true

module Tasker
  class AnnotationTypeSerializer < ActiveModel::Serializer
    attributes :annotation_type_id, :name, :description
  end
end
