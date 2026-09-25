# frozen_string_literal: true

module RubyLsp
  module Dragonruby
    class Registry
      class PrimitiveSchema
        attr_reader :name, :primitive_marker, :keys

        def initialize(name:, keys: [], primitive_marker: nil)
          @name = name
          @primitive_marker = primitive_marker
          @keys = keys.freeze
          @keys_by_name = @keys.to_h { |key| [key.name, key] }.freeze
          freeze
        end

        def key(name)
          @keys_by_name[name]
        end

        def key?(name)
          @keys_by_name.key?(name)
        end
      end
    end
  end
end
