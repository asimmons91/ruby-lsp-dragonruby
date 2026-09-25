# frozen_string_literal: true

module RubyLsp
  module Dragonruby
    class Registry
      class Returns
        attr_reader :names

        def initialize(names)
          @names = names.map(&:to_s).freeze
          freeze
        end

        def unknown?
          @names == [UNKNOWN]
        end

        def union?
          @names.size > 1
        end

        def to_s
          @names.join(" | ")
        end
      end
    end
  end
end
