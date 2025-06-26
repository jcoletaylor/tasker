# frozen_string_literal: true

require 'concurrent-ruby'

module Tasker
  module Telemetry
    # MetricTypes provides thread-safe metric storage classes for high-performance telemetry
    #
    # This module implements the core metric types for Tasker's native metrics collection
    # backend. All metric types are thread-safe using atomic operations and follow
    # Tasker's fail-fast principles with explicit error handling.
    #
    # @example Basic metric operations
    #   counter = Counter.new('tasks_completed')
    #   counter.increment                    # +1
    #   counter.increment(5)                 # +5
    #   counter.value                        # → current count
    #
    # @example Gauge operations
    #   gauge = Gauge.new('active_tasks')
    #   gauge.set(42)                        # Set to specific value
    #   gauge.increment                      # +1
    #   gauge.decrement(3)                   # -3
    #
    module MetricTypes
      # Counter represents a monotonically increasing metric value
      #
      # Counters are thread-safe and use atomic operations for increment operations.
      # They follow the fail-fast principle with explicit validation and meaningful
      # error messages for invalid operations.
      #
      # @example Production usage
      #   counter = Counter.new('api_requests_total', labels: { endpoint: '/tasks' })
      #   counter.increment                  # Increment by 1
      #   counter.increment(batch_size)      # Increment by batch size
      #   counter.value                      # Get current value (thread-safe read)
      #
      class Counter
        # @return [String] The metric name
        attr_reader :name

        # @return [Hash] The metric labels for dimensional data
        attr_reader :labels

        # @return [Time] When this metric was first created
        attr_reader :created_at

        # Initialize a new counter metric
        #
        # @param name [String] The metric name (must be present)
        # @param labels [Hash] Optional labels for dimensional metrics
        # @raise [ArgumentError] If name is nil or empty
        def initialize(name, labels: {})
          raise ArgumentError, 'Metric name cannot be nil or empty' if name.nil? || name.strip.empty?

          @name = name.to_s.freeze
          @labels = labels.freeze
          @value = Concurrent::AtomicFixnum.new(0)
          @created_at = Time.current.freeze
        end

        # Increment the counter by a specified amount
        #
        # @param amount [Integer] Amount to increment (must be non-negative)
        # @return [Integer] The new counter value
        # @raise [ArgumentError] If amount is negative or not an integer
        def increment(amount = 1)
          return false unless amount.is_a?(Integer)
          raise ArgumentError, "Counter increment amount must be positive, got: #{amount}" if amount.negative?

          @value.update { |current| current + amount }
        end

        # Get the current counter value (thread-safe read)
        #
        # @return [Integer] Current counter value
        delegate :value, to: :@value

        # Reset the counter to zero (primarily for testing)
        #
        # @return [Integer] The reset value (0)
        def reset!
          @value.value = 0
        end

        # Get a hash representation of this metric
        #
        # @return [Hash] Metric data including name, labels, value, type
        def to_h
          {
            name: name,
            labels: labels,
            value: value,
            type: :counter,
            created_at: created_at
          }
        end

        # Get a description of this metric for debugging
        #
        # @return [String] Human-readable description
        def description
          label_str = labels.empty? ? '' : labels.inspect
          "#{name}#{label_str} = #{value} (counter)"
        end
      end

      # Gauge represents a metric value that can go up or down
      #
      # Gauges are thread-safe and support atomic set, increment, and decrement
      # operations. They follow fail-fast principles with explicit validation.
      #
      # @example Production usage
      #   gauge = Gauge.new('active_connections')
      #   gauge.set(100)                     # Set to specific value
      #   gauge.increment(5)                 # +5 connections
      #   gauge.decrement(2)                 # -2 connections
      #   gauge.value                        # Get current value
      #
      class Gauge
        # @return [String] The metric name
        attr_reader :name

        # @return [Hash] The metric labels for dimensional data
        attr_reader :labels

        # @return [Time] When this metric was first created
        attr_reader :created_at

        # Initialize a new gauge metric
        #
        # @param name [String] The metric name (must be present)
        # @param labels [Hash] Optional labels for dimensional metrics
        # @param initial_value [Numeric] Initial gauge value
        # @raise [ArgumentError] If name is nil or empty, or initial_value is not numeric
        def initialize(name, labels: {}, initial_value: 0)
          raise ArgumentError, 'Metric name cannot be nil or empty' if name.nil? || name.strip.empty?

          unless initial_value.is_a?(Numeric)
            raise ArgumentError,
                  "Initial value must be numeric, got: #{initial_value.class}"
          end

          @name = name.to_s.freeze
          @labels = labels.freeze
          @value = Concurrent::AtomicReference.new(initial_value)
          @created_at = Time.current.freeze
        end

        # Set the gauge to a specific value
        #
        # @param new_value [Numeric] The new gauge value
        # @return [Numeric] The new gauge value
        # @raise [ArgumentError] If new_value is not numeric
        def set(new_value)
          raise ArgumentError, "Gauge value must be numeric, got: #{new_value.class}" unless new_value.is_a?(Numeric)

          @value.set(new_value)
          new_value
        end

        # Increment the gauge by a specified amount
        #
        # @param amount [Numeric] Amount to increment (can be negative)
        # @return [Numeric] The new gauge value
        # @raise [ArgumentError] If amount is not numeric
        def increment(amount = 1)
          unless amount.is_a?(Numeric)
            raise ArgumentError,
                  "Gauge increment amount must be numeric, got: #{amount.class}"
          end

          @value.update { |current| current + amount }
        end

        # Decrement the gauge by a specified amount
        #
        # @param amount [Numeric] Amount to decrement (must be positive)
        # @return [Numeric] The new gauge value
        # @raise [ArgumentError] If amount is not numeric or is negative
        def decrement(amount = 1)
          unless amount.is_a?(Numeric)
            raise ArgumentError,
                  "Gauge decrement amount must be numeric, got: #{amount.class}"
          end
          raise ArgumentError, "Gauge decrement amount must be positive, got: #{amount}" if amount.negative?

          increment(-amount)
        end

        # Get the current gauge value (thread-safe read)
        #
        # @return [Numeric] Current gauge value
        def value
          @value.get
        end

        # Get a hash representation of this metric
        #
        # @return [Hash] Metric data including name, labels, value, type
        def to_h
          {
            name: name,
            labels: labels,
            value: value,
            type: :gauge,
            created_at: created_at
          }
        end

        # Get a description of this metric for debugging
        #
        # @return [String] Human-readable description
        def description
          label_str = labels.empty? ? '' : labels.inspect
          "#{name}#{label_str} = #{value} (gauge)"
        end
      end

      # Histogram represents a metric that samples observations and counts them in buckets
      #
      # Histograms are thread-safe and provide statistical analysis of observed values.
      # They track count, sum, and bucket distributions for duration and size metrics.
      #
      # @example Production usage
      #   histogram = Histogram.new('task_duration_seconds', buckets: [0.1, 0.5, 1.0, 5.0])
      #   histogram.observe(0.45)            # Record a 0.45 second duration
      #   histogram.observe(2.1)             # Record a 2.1 second duration
      #   histogram.count                    # Total observations
      #   histogram.sum                      # Sum of all observed values
      #   histogram.buckets                  # Bucket counts
      #
      class Histogram
        # @return [String] The metric name
        attr_reader :name

        # @return [Hash] The metric labels for dimensional data
        attr_reader :labels

        # @return [Array<Numeric>] The histogram bucket boundaries
        attr_reader :bucket_boundaries

        # @return [Time] When this metric was first created
        attr_reader :created_at

        # Default bucket boundaries for duration metrics (in seconds)
        DEFAULT_BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0].freeze

        # Initialize a new histogram metric
        #
        # @param name [String] The metric name (must be present)
        # @param labels [Hash] Optional labels for dimensional metrics
        # @param buckets [Array<Numeric>] Bucket boundaries (must be sorted ascending)
        # @raise [ArgumentError] If name is nil/empty or buckets are invalid
        def initialize(name, labels: {}, buckets: DEFAULT_BUCKETS)
          raise ArgumentError, 'Metric name cannot be nil or empty' if name.nil? || name.strip.empty?
          raise ArgumentError, 'Buckets must be an array' unless buckets.is_a?(Array)
          raise ArgumentError, 'Buckets cannot be empty' if buckets.empty?

          @name = name.to_s.freeze
          @labels = labels.freeze
          @bucket_boundaries = buckets.sort.freeze
          @created_at = Time.current.freeze

          # Thread-safe counters for each bucket + infinity bucket
          @bucket_counts = (@bucket_boundaries + [Float::INFINITY]).map do |_|
            Concurrent::AtomicFixnum.new(0)
          end

          @count = Concurrent::AtomicFixnum.new(0)
          @sum = Concurrent::AtomicReference.new(0.0)
        end

        # Observe a value and update histogram buckets
        #
        # @param value [Numeric] The observed value
        # @return [Numeric] The observed value (for chaining)
        # @raise [ArgumentError] If value is not numeric
        def observe(value)
          raise ArgumentError, "Observed value must be numeric, got: #{value.class}" unless value.is_a?(Numeric)

          # Update count and sum atomically
          @count.increment
          @sum.update { |current| current + value }

          # Increment all buckets where value <= boundary (cumulative histogram)
          @bucket_boundaries.each_with_index do |boundary, index|
            @bucket_counts[index].increment if value <= boundary
          end

          # Always increment the infinity bucket (total count)
          @bucket_counts.last.increment

          value
        end

        # Get the total number of observations
        #
        # @return [Integer] Total observation count
        def count
          @count.value
        end

        # Get the sum of all observed values
        #
        # @return [Numeric] Sum of observations
        def sum
          @sum.get
        end

        # Get the current bucket counts
        #
        # @return [Hash] Bucket boundaries to counts mapping
        def buckets
          result = {}
          @bucket_boundaries.each_with_index do |boundary, index|
            result[boundary] = @bucket_counts[index].value
          end
          result[Float::INFINITY] = @bucket_counts.last.value
          result
        end

        # Calculate the average of observed values
        #
        # @return [Float] Average value, or 0.0 if no observations
        def average
          current_count = count
          return 0.0 if current_count.zero?

          sum.to_f / current_count
        end

        # Get a hash representation of this metric
        #
        # @return [Hash] Metric data including name, labels, buckets, count, sum, type
        def to_h
          {
            name: name,
            labels: labels,
            buckets: buckets,
            count: count,
            sum: sum,
            average: average,
            type: :histogram,
            created_at: created_at
          }
        end

        # Get a description of this metric for debugging
        #
        # @return [String] Human-readable description
        def description
          label_str = labels.empty? ? '' : labels.inspect
          "#{name}#{label_str} = #{count} observations, avg: #{average.round(3)} (histogram)"
        end

        # Reset the histogram (primarily for testing)
        #
        # @return [void]
        def reset!
          @count.value = 0
          @sum.set(0.0)
          @bucket_counts.each { |bucket| bucket.value = 0 }
        end
      end
    end
  end
end
