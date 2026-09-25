# frozen_string_literal: true

module RubyLsp
  module Dragonruby
    class Registry
      class Accessor
        attr_reader :name, :returns, :doc

        def initialize(name:, returns:, doc:)
          @name = name
          @returns = returns
          @doc = doc
          freeze
        end
      end
    end
  end
end
