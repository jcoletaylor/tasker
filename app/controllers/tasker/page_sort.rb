# typed: false
# frozen_string_literal: true

module Tasker
  module PageSort
    extend ActiveSupport::Concern
    def build_page_sort_params(model_name, default_sort)
      @page_sort_params = PageSortParamsBuilder.build(request.params, model_name, default_sort)
    end

    def page_sort_params
      @page_sort_params
    end

    # Service class to build page sort parameters
    # Reduces complexity by organizing parameter processing logic
    class PageSortParamsBuilder
      class << self
        # Build page sort parameters from request params
        #
        # @param params [Hash] Request parameters
        # @param model_name [String/Symbol] Model name for validation
        # @param default_sort [Symbol] Default sort column
        # @return [Hash] Page sort parameters
        def build(params, model_name, default_sort)
          valid_sorts = extract_valid_sorts(model_name)

          {
            limit: extract_limit(params),
            offset: extract_offset(params),
            order: build_order_hash(params, valid_sorts, default_sort)
          }
        end

        private

        # Extract valid sort columns from model
        #
        # @param model_name [String/Symbol] Model name
        # @return [Array<Symbol>] Valid sort columns
        def extract_valid_sorts(model_name)
          model = model_name.to_s.camelize.constantize
          model.column_names.map(&:to_sym)
        end

        # Extract limit parameter with default
        #
        # @param params [Hash] Request parameters
        # @return [Integer] Limit value
        def extract_limit(params)
          params[:limit] || 20
        end

        # Extract offset parameter with default
        #
        # @param params [Hash] Request parameters
        # @return [Integer] Offset value
        def extract_offset(params)
          params[:offset] || 0
        end

        # Build order hash with validation
        #
        # @param params [Hash] Request parameters
        # @param valid_sorts [Array<Symbol>] Valid sort columns
        # @param default_sort [Symbol] Default sort column
        # @return [Hash] Order hash
        def build_order_hash(params, valid_sorts, default_sort)
          sort_by = extract_sort_by(params, valid_sorts, default_sort)
          sort_order = extract_sort_order(params)

          { sort_by => sort_order }
        end

        # Extract and validate sort_by parameter
        #
        # @param params [Hash] Request parameters
        # @param valid_sorts [Array<Symbol>] Valid sort columns
        # @param default_sort [Symbol] Default sort column
        # @return [Symbol] Validated sort column
        def extract_sort_by(params, valid_sorts, default_sort)
          sort_by = params[:sort_by] ? params[:sort_by].to_sym : default_sort
          valid_sorts.include?(sort_by) ? sort_by : default_sort
        end

        # Extract and validate sort_order parameter
        #
        # @param params [Hash] Request parameters
        # @return [Symbol] Validated sort order
        def extract_sort_order(params)
          sort_order = params[:sort_order] ? params[:sort_order].to_sym : :asc
          %i[asc desc].include?(sort_order) ? sort_order : :asc
        end
      end
    end
  end
end
