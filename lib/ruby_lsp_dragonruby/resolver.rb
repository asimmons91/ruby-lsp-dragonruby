# frozen_string_literal: true

require "prism"

require_relative "local_aliases"

module RubyLsp
  module Dragonruby
    # Resolves an expression to a DragonRuby type by walking chains left to
    # right through registry member returns.
    class Resolver
      def initialize(registry, roots: nil, index: nil)
        @registry = registry
        @roots = roots || Roots.new(registry, index: index)
        @aliases = LocalAliases.new
        @resolving = {}
      end

      def resolve(node, context = nil)
        return Resolution.unknown unless node

        case node
        when Prism::ParenthesesNode
          resolve_parentheses(node, context)
        when Prism::LocalVariableReadNode
          resolve_local(node, context)
        when Prism::CallNode
          resolve_call(node, context)
        else
          resolve_root(node, context)
        end
      end

      private

      # A local variable resolves to the value of its nearest preceding
      # assignment. Without one it falls through to the root strategies, so
      # method parameters still work; a reassignment to an expression that
      # does not resolve replaces the earlier type from that point on.
      def resolve_local(node, context)
        assignment = @aliases.assignment_for(node, context)
        return resolve_root(node, context) unless assignment
        return Resolution.unknown if resolving?(assignment)

        @resolving[assignment.object_id] = true
        begin
          resolve_alias_value(assignment, context)
        ensure
          @resolving.delete(assignment.object_id)
        end
      end

      def resolve_alias_value(assignment, context)
        case assignment
        when Prism::LocalVariableWriteNode, Prism::LocalVariableOrWriteNode, Prism::LocalVariableAndWriteNode
          resolve(assignment.value, context)
        else
          Resolution.unknown
        end
      end

      def resolving?(assignment)
        @resolving[assignment.object_id]
      end

      def resolve_parentheses(node, context)
        body = node.body
        return Resolution.unknown unless body.is_a?(Prism::StatementsNode) && body.body.size == 1

        resolve(body.body.first, context)
      end

      def resolve_call(node, context)
        if node.receiver.nil? || node.receiver.is_a?(Prism::SelfNode)
          type = @roots.resolve(node, context)
          return Resolution.of_type(type) if type
          return Resolution.unknown if node.receiver.nil?
        end

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
