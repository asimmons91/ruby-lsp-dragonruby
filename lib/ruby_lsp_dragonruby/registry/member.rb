# frozen_string_literal: true

module RubyLsp
  module Dragonruby
    class Registry
      class Member
        attr_reader :name, :kind, :params, :returns, :doc, :docs_url, :aliases, :scope

        def initialize(name:, kind:, returns:, doc:, params: [], docs_url: nil, aliases: [], scope: :instance)
          @name = name
          @kind = kind
          @params = params.freeze
          @returns = returns
          @doc = doc
          @docs_url = docs_url
          @aliases = aliases.freeze
          @scope = scope
          freeze
        end

        def method?
          @kind == :method
        end

        def attribute?
          @kind == :attribute
        end

        # Members offered on instances (the default). `both` is offered for
        # both instance and class receivers, `class` only on constants.
        def offered_for?(receiver_scope)
          @scope == :both || @scope == receiver_scope
        end

        def signatures
          [@name, *@aliases]
        end
      end
    end
  end
end
