# frozen_string_literal: true

require "prism"

require_relative "local_aliases"

module RubyLsp
  module Dragonruby
    # Resolves an expression to a DragonRuby type by walking chains left to
    # right through registry member returns. Argument-free calls on the state
    # root and on state sub-paths resolve to dynamic `args.state` paths.
    class Resolver
      def initialize(registry, roots: nil, index: nil, state_store: nil)
        @registry = registry
        @roots = roots || Roots.new(registry, index: index)
        @aliases = LocalAliases.new
        @state_store = state_store
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

      # Drops memoized alias scope walks; bulk consumers call this before
      # resolving a whole new parse.
      def reset_aliases!
        @aliases.reset!
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
        return Resolution.unknown unless receiver.confident?

        if receiver.resolved_type?
          resolve_typed_member(node, receiver.type)
        elsif receiver.state_path?
          resolve_state_member(node, receiver.state_path)
        else
          Resolution.unknown
        end
      end

      def resolve_typed_member(node, type)
        member = type.member(node.name.to_s)
        return resolution_for(member.returns) if member
        return Resolution.of_state(node.name.to_s) if @registry.state_type?(type) && plain_call?(node)

        Resolution.unknown
      end

      # A known child path wins over a curated entity member of the same name,
      # because the write is what created the path. Argument-free unknown names
      # extend the path even before anything writes them, so completion can
      # follow a chain that is only written elsewhere.
      def resolve_state_member(node, path)
        candidate = "#{path}.#{node.name}"
        member = @registry.entity_type&.member(node.name.to_s)
        known = @state_store&.path?(candidate)
        plain = plain_call?(node)

        if member && !plain
          resolution_for(member.returns)
        elsif known && plain
          Resolution.of_state(candidate)
        elsif member
          resolution_for(member.returns)
        elsif plain
          Resolution.of_state(candidate)
        else
          Resolution.unknown
        end
      end

      def plain_call?(node)
        node.arguments.nil? && node.opening_loc.nil? && node.block.nil?
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
