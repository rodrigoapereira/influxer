require 'influxer/metrics/relation'
require 'influxer/metrics/scoping'
require 'active_model'

module Influxer
  class MetricsError < StandardError; end
  class MetricsInvalid < MetricsError; end

  # Base class for InfluxDB querying and writing
  # rubocop:disable Metrics/ClassLength
  class Metrics
    include ActiveModel::Model
    include ActiveModel::Validations
    extend ActiveModel::Callbacks

    include Influxer::Scoping

    define_model_callbacks :write

    class << self
      # delegate query functions to all
      delegate(
        *(
          [
            :write, :write!, :select, :where,
            :group, :time, :past, :since,
            :limit, :offset, :fill, :delete_all
          ] + Influxer::Calculations::CALCULATION_METHODS
        ),
        to: :all
      )

      attr_reader :series
      attr_accessor :tag_names
      attr_accessor :value_names

      def attributes(*attrs)
        attrs.each do |name|
          define_method("#{name}=") do |val|
            @attributes[name] = val
          end

          define_method("#{name}") do
            @attributes[name]
          end
        end
      end

      def values(*attrs)
        attributes(*attrs)
        self.value_names ||= []
        self.value_names += attrs.map(&:to_s)
      end

      def tags(*attrs)
        attributes(*attrs)
        self.tag_names ||= []
        self.tag_names += attrs.map(&:to_s)
      end

      def tag?(name)
        tag_names.include?(name.to_s)
      end

      def inherited(subclass)
        subclass.set_series
        subclass.tag_names = tag_names.nil? ? [] : tag_names.dup
      end

      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/AbcSize
      def set_series(*args)
        if args.empty?
          matches = to_s.match(/^(.*)Metrics$/)
          if matches.nil?
            @series = superclass.respond_to?(:series) ? superclass.series : to_s.underscore
          else
            @series = matches[1].split("::").join("_").underscore
          end
        elsif args.first.is_a?(Proc)
          @series = args.first
        else
          @series = args
        end
      end
      # rubocop:enable Metrics/MethodLength
      # rubocop:enable Metrics/AbcSize

      def all
        if current_scope
          current_scope.clone
        else
          default_scoped
        end
      end

      # rubocop:disable Metrics/MethodLength
      def quoted_series(val = @series, instance = nil)
        case val
        when Regexp
          val.inspect
        when Proc
          quoted_series(val.call(instance))
        when Array
          if val.length > 1
            "merge(#{val.map { |s| quoted_series(s) }.join(',')})"
          else
            quoted_series(val.first)
          end
        else
          '"' + val.to_s.gsub(/\"/) { %q(\") } + '"'
        end
      end
      # rubocop:enable Metrics/MethodLength
    end

    delegate :tag_names, to: :class
    delegate :value_names, to: :class

    def initialize(attributes = {})
      @attributes = {}
      @persisted = false
      super
    end

    def write
      fail MetricsError if self.persisted?

      return false if self.invalid?

      run_callbacks :write do
        write_point
      end
      self
    end

    def write!
      fail MetricsInvalid if self.invalid?
      write
    end

    def write_point
      client.write_point unquote(series), build_write_point_params
      @persisted = true
    end

    def persisted?
      @persisted
    end

    def series
      self.class.quoted_series(self.class.series, self)
    end

    def client
      Influxer.client
    end

    def dup
      self.class.new(@attributes)
    end

    # Returns hash with metrics values
    def values
      @attributes.select { |k, _| value_names.include?(k.to_s) }
    end

    # Returns hash with metrics tags
    def tags
      @attributes.select { |k, _| tag_names.include?(k.to_s) }
    end

    def time(parse = false)
      return unless @time

      return parse_timestamp(@time) if parse
      @time
    end

    def time=(val)
      if val.is_a?(Date) || val.is_a?(Time)
        @time = parse_time(val)
      else
        @time
      end
    end

    private

    def parse_timestamp(val)
      case client.time_precision
      when 'ms'
        Time.at(val / 1_000.0)
      else
        Time.at(val)
      end
    end

    def parse_time(val)
      case client.time_precision
      when 'ms'
        (val.to_f * 1_000).to_i
      else
        val.to_i
      end
    end

    def build_write_point_params
      hash = {}
      hash.store(:values, values)
      hash.store(:tags, tags)
      hash.store(:timestamp, time) if time

      hash
    end

    def unquote(name)
      name.gsub(/(\A['"]|['"]\z)/, '')
    end
  end
end
