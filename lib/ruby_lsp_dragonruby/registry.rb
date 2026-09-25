# frozen_string_literal: true

require_relative "registry/issue"
require_relative "registry/metadata"
require_relative "registry/returns"
require_relative "registry/param"
require_relative "registry/member"
require_relative "registry/primitive_key"
require_relative "registry/primitive_schema"
require_relative "registry/type"
require_relative "registry/accessor"
require_relative "registry/macro"
require_relative "registry/name_list"
require_relative "registry/family_expansion"
require_relative "registry/validator"
require_relative "registry/loader"
require_relative "registry/coverage"

module RubyLsp
  module Dragonruby
    class Registry
      class InvalidDataError < StandardError; end

      DATA_DIR = File.expand_path("../../data", __dir__)
      UNKNOWN = "Unknown"
      UNSET = Object.new.freeze
      STATE_ROOT = "GTK::State"
      STATE_ENTITY = "GTK::Entity"
      CORE_TYPES = %w[
        Array
        Boolean
        Float
        Hash
        Integer
        Numeric
        Object
        Proc
        Range
        String
        Symbol
      ].freeze

      class << self
        def load(data_dir: DATA_DIR, logger: nil)
          @default ||= Loader.new(data_dir: data_dir, logger: logger).load
        end

        attr_reader :default

        def reset!
          @default = nil
        end

        def validate!(data_dir: DATA_DIR, logger: nil)
          issues = Loader.new(data_dir: data_dir, logger: logger).validation_issues
          errors = issues.select(&:error?)
          raise InvalidDataError, errors.join("\n") if errors.any?

          issues
        end
      end

      attr_reader :metadata, :types, :schemas, :macros

      def initialize(metadata:, types:, schemas:, macros: {})
        @metadata = metadata
        @types = types.freeze
        @schemas = schemas.freeze
        @macros = macros.freeze
        @core_types = CORE_TYPES.to_set.freeze
        freeze
      end

      def type(name)
        @types[name]
      end

      # The type that roots dynamic state paths (`args.state`).
      def state_type
        @types[STATE_ROOT]
      end

      def state_type?(type)
        !type.nil? && type.name == STATE_ROOT
      end

      # The type whose curated members are offered under a state sub-path.
      def entity_type
        @types[STATE_ENTITY]
      end

      def schema(name)
        @schemas[name]
      end

      def macro(name)
        @macros[name]
      end

      # The macros callable under any of their names or aliases.
      def macros_for_call_name(name)
        @macros.values.select { |macro| macro.all_names.include?(name) }
      end

      # The primitive schemas accepted by a collection type.
      def primitive_schemas_for(type)
        return [] unless type&.accepts_primitive

        type.accepts_primitive.filter_map { |name| @schemas[name] }
      end

      def type_names
        @types.keys
      end

      def core_type?(name)
        @core_types.include?(name)
      end

      def known_type?(name)
        name == UNKNOWN || core_type?(name) || @types.key?(name)
      end
    end
  end
end
