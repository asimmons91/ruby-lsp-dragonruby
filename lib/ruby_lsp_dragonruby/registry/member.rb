# frozen_string_literal: true

module RubyLsp
  module Dragonruby
    class Registry
      class Member
        attr_reader :name, :kind, :params, :returns, :doc, :docs_url, :aliases

        def initialize(name:, kind:, returns:, doc:, params: [], docs_url: nil, aliases: [])
          @name = name
          @kind = kind
          @params = params.freeze
          @returns = returns
          @doc = doc
          @docs_url = docs_url
          @aliases = aliases.freeze
          freeze
        end

        def method?
          @kind == :method
        end

        def attribute?
          @kind == :attribute
        end

        def signatures
          [@name, *@aliases]
        end
      end
    end
  end
end
