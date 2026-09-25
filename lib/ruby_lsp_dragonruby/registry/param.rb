# frozen_string_literal: true

module RubyLsp
  module Dragonruby
    class Registry
      class Param
        attr_reader :name, :kind, :type

        def initialize(name:, kind:, type:)
          @name = name
          @kind = kind
          @type = type
          freeze
        end

        def block?
          @kind == :block
        end
      end
    end
  end
end
