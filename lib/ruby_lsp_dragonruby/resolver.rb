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
        when Prism::IntegerNode
          Resolution.of_core("Integer")
        when Prism::FloatNode
          Resolution.of_core("Float")
        when Prism::HashNode
          Resolution.of_core("Hash")
        when Prism::ArrayNode
          Resolution.of_core("Array")
        when Prism::StringNode, Prism::InterpolatedStringNode
          Resolution.of_core("String")
        when Prism::SymbolNode
          Resolution.of_core("Symbol")
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
          return resolve_kernel_member(node) if node.receiver.nil?
        end

        receiver = resolve(node.receiver, context)
        return Resolution.unknown unless receiver.confident?

        if receiver.resolved_type?
          resolve_typed_member(node, receiver.type)
        elsif receiver.core?
          resolve_core_member(node, receiver.core_type)
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

      # Core extensions hang off core types reached through literals, registry
      # returns, or the `Kernel` receiverless helpers.
      def resolve_core_member(node, core_type)
        member = core_extension_member(core_type, node.name)
        member ? resolution_for(member.returns) : Resolution.unknown
      end

      def resolve_kernel_member(node)
        resolve_core_member(node, "Kernel")
      end

      # A known child path wins over a curated entity member of the same name,
      # because the write is what created the path. Argument-free unknown names
      # extend the path even before anything writes them, so completion can
      # follow a chain that is only written elsewhere. Core extensions apply
      # when a state value's inferred type is a core class (REQ-M6-03).
      def resolve_state_member(node, path)
        candidate = "#{path}.#{node.name}"
        member = @registry.entity_type&.member(node.name.to_s)
        known = @state_store&.path?(candidate)
        plain = plain_call?(node)

        if member && !plain
          resolution_for(member.returns)
        elsif known && plain
          Resolution.of_state(candidate)
        elsif (extension = state_core_extension_member(path, node.name))
          resolution_for(extension.returns)
        elsif member
          resolution_for(member.returns)
        elsif plain
          Resolution.of_state(candidate)
        else
          Resolution.unknown
        end
      end

      # The first curated core extension member matching `name` among the
      # inferred types of a state path.
      def state_core_extension_member(path, name)
        entry = @state_store&.entry(path)
        return unless entry

        entry.types.each do |type_name|
          member = core_extension_member(type_name, name)
          return member if member
        end
        nil
      end

      def core_extension_member(core_type, name)
        extension = @registry.core_extension_type(core_type)
        extension&.member(name.to_s)
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
        return Resolution.of_type(type) if type && !type.core_extension?
        return Resolution.of_core(name) if @registry.core_type?(name)

        Resolution.unknown
      end
    end
  end
end
