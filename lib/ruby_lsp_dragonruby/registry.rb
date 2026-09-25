# frozen_string_literal: true

require_relative "registry/issue"
require_relative "registry/metadata"
require_relative "registry/returns"
require_relative "registry/param"
require_relative "registry/member"
require_relative "registry/primitive_key"
require_relative "registry/primitive_schema"
require_relative "registry/type"
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

      attr_reader :metadata, :types, :schemas

      def initialize(metadata:, types:, schemas:)
        @metadata = metadata
        @types = types.freeze
        @schemas = schemas.freeze
        @core_types = CORE_TYPES.to_set.freeze
        freeze
      end

      def type(name)
        @types[name]
      end

      def schema(name)
        @schemas[name]
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
