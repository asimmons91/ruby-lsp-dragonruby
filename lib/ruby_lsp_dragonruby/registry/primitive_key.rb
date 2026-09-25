# frozen_string_literal: true

module RubyLsp
  module Dragonruby
    class Registry
      class PrimitiveKey
        attr_reader :name, :type, :default, :doc, :allowed_values

        def initialize(name:, type:, doc:, default: UNSET, allowed_values: nil)
          @name = name
          @type = type
          @default = default
          @doc = doc
          @allowed_values = allowed_values&.freeze
          freeze
        end

        def default?
          !@default.equal?(UNSET)
        end
      end
    end
  end
end
