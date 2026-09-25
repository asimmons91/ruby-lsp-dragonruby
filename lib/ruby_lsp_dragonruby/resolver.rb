# frozen_string_literal: true

require "prism"

module RubyLsp
  module Dragonruby
    # Resolves an expression to a DragonRuby type by walking chains left to
    # right through registry member returns.
    class Resolver
      def initialize(registry, roots: nil)
        @registry = registry
        @roots = roots || Roots.new(registry)
      end

      def resolve(node, context = nil)
        return Resolution.unknown unless node

        case node
        when Prism::ParenthesesNode
          resolve_parentheses(node, context)
        when Prism::CallNode
          resolve_call(node, context)
        else
          resolve_root(node, context)
        end
      end

      private

      def resolve_parentheses(node, context)
        body = node.body
        return Resolution.unknown unless body.is_a?(Prism::StatementsNode) && body.body.size == 1

        resolve(body.body.first, context)
      end

      def resolve_call(node, context)
        return resolve_root(node, context) unless node.receiver

        receiver = resolve(node.receiver, context)
        return Resolution.unknown unless receiver.resolved_type?

        member = receiver.type.member(node.name.to_s)
        return Resolution.unknown unless member

        resolution_for(member.returns)
      end

      def resolve_root(node, context)
        type = @roots.resolve(node, context)
        type ? Resolution.of_type(type) : Resolution.unknown
      end

      def resolution_for(returns)
        names = returns.names
        return Resolution.unknown if returns.unknown? || names.size != 1

        name = names.first
        type = @registry.type(name)
        return Resolution.of_type(type) if type
        return Resolution.of_core(name) if @registry.core_type?(name)

        Resolution.unknown
      end
    end
  end
end
